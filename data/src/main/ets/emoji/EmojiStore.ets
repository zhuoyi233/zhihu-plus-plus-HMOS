import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ZHIHU_USER_AGENT } from '../network/ZhihuHttpClient';
import {
  decodeStickerDataUrl,
  EmojiSticker,
  emojiFileName,
  EMOJI_CACHE_VERSION,
  EMOJI_STICKER_API_URL,
  parseStickerResponse
} from './EmojiRules';

const TAG = 'EmojiStore';
const EMOJI_DIRECTORY = 'emojis';
const EMOJI_MAPPING_FILE = 'emoji_mapping.json';
const EMOJI_VERSION_FILE = 'emoji_version.txt';
const EMOJI_CONNECT_TIMEOUT_MS = 10000;
const EMOJI_READ_TIMEOUT_MS = 15000;
/** 表情表响应含 56 张 base64 PNG，实测约 0.4MB；留足余量防后续扩容被截断。 */
const EMOJI_RESPONSE_LIMIT_BYTES = 8 * 1024 * 1024;

/**
 * 知乎小表情仓库，对齐上游 EmojiManager：首次使用从 sticker-group API 拉取
 * （placeholder + base64 PNG），解码后落盘 filesDir/emojis，并缓存
 * placeholder → 文件名映射；版本不一致或下载失败时回退本地缓存。
 * 目录、文件名均由固定常量与 API 返回的数字 id 构成，不引入用户可控路径。
 */
export class EmojiStore {
  private static instance?: EmojiStore;

  static getInstance(): EmojiStore {
    if (EmojiStore.instance === undefined) {
      EmojiStore.instance = new EmojiStore();
    }
    return EmojiStore.instance;
  }

  /** placeholder → 文件名。 */
  private readonly mapping: Record<string, string> = {};
  /** 文件名 → 本地绝对路径。 */
  private readonly cache: Record<string, string> = {};
  private placeholderList: Array<string> = [];
  private catalogVersion: number = 0;
  private loading?: Promise<void>;

  get version(): number {
    return this.catalogVersion;
  }

  /** 返回 file:// URI 形式（部分系统版本 Image 对裸沙箱路径不加载），未命中返回空串。 */
  path(placeholder: string): string {
    const fileName = this.mapping[placeholder];
    if (fileName === undefined) {
      return '';
    }
    return this.toImageUri(this.cache[fileName] ?? '');
  }

  pathByFileName(fileName: string): string {
    return this.toImageUri(this.cache[fileName] ?? '');
  }

  private toImageUri(path: string): string {
    return path.length > 0 ? `file://${path}` : '';
  }

  placeholders(): Array<string> {
    return this.placeholderList;
  }

  /**
   * 幂等加载：并发调用合并为同一次加载，成功或回退缓存后广播
   * `emojiCatalogVersion` 供 UI 重建。
   */
  ensureLoaded(context: common.Context): Promise<void> {
    if (this.loading !== undefined) {
      return this.loading;
    }
    if (this.catalogVersion > 0) {
      return Promise.resolve();
    }
    const directory = `${context.filesDir}/${EMOJI_DIRECTORY}`;
    this.loading = this.loadOrDownload(directory).then((): void => {
      this.loading = undefined;
    }, (): void => {
      this.loading = undefined;
    });
    return this.loading;
  }

  private async loadOrDownload(directory: string): Promise<void> {
    try {
      if (await this.loadFromCache(directory)) {
        this.catalogVersion += 1;
        this.broadcast();
        return;
      }
      await this.downloadAndCache(directory);
      this.catalogVersion += 1;
      this.broadcast();
    } catch (error) {
      hilog.warn(0xD001, TAG, 'download failed, fallback to cache: %{public}s',
        error instanceof Error ? error.message : 'unknown');
      if (await this.loadFromCache(directory)) {
        this.catalogVersion += 1;
        this.broadcast();
        return;
      }
      // 保持未初始化：下次进入评论/通知页可再次尝试下载。
    }
  }

  private async loadFromCache(directory: string): Promise<boolean> {
    const mappingPath = `${directory}/${EMOJI_MAPPING_FILE}`;
    const versionPath = `${directory}/${EMOJI_VERSION_FILE}`;
    if (!(await fileIo.access(mappingPath)) || !(await fileIo.access(versionPath))) {
      return false;
    }
    const version = (await fileIo.readText(versionPath)).trim();
    if (version !== EMOJI_CACHE_VERSION) {
      return false;
    }
    let parsed: Record<string, string>;
    try {
      parsed = JSON.parse(await fileIo.readText(mappingPath)) as Record<string, string>;
    } catch (_error) {
      return false;
    }
    for (const placeholder of Object.keys(parsed)) {
      const fileName = parsed[placeholder];
      if (typeof fileName !== 'string' || fileName.length === 0) {
        continue;
      }
      const path = `${directory}/${fileName}`;
      if (await fileIo.access(path)) {
        this.mapping[placeholder] = fileName;
        this.cache[fileName] = path;
      }
    }
    this.rebuildPlaceholders();
    return this.placeholderList.length > 0;
  }

  private async downloadAndCache(directory: string): Promise<void> {
    const body = await this.fetchStickerGroup();
    const stickers = parseStickerResponse(body);
    if (stickers.length === 0) {
      throw new Error('Emoji sticker response is empty');
    }
    await fileIo.mkdir(directory, true);
    const mapping: Record<string, string> = {};
    for (const sticker of stickers) {
      const path = await this.writeStickerImage(directory, sticker);
      if (path === undefined) {
        continue;
      }
      const fileName = emojiFileName(sticker.id);
      mapping[sticker.placeholder] = fileName;
      this.cache[fileName] = path;
    }
    if (Object.keys(mapping).length === 0) {
      throw new Error('Emoji sticker images are all invalid');
    }
    for (const placeholder of Object.keys(mapping)) {
      this.mapping[placeholder] = mapping[placeholder];
    }
    this.rebuildPlaceholders();
    await this.writeTextFile(`${directory}/${EMOJI_MAPPING_FILE}`, JSON.stringify(mapping));
    await this.writeTextFile(`${directory}/${EMOJI_VERSION_FILE}`, EMOJI_CACHE_VERSION);
    hilog.info(0xD001, TAG, 'cached %{public}d emojis', Object.keys(mapping).length);
  }

  private async writeTextFile(path: string, content: string): Promise<void> {
    const file = await fileIo.open(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE |
      fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, content);
    } finally {
      await fileIo.close(file);
    }
  }

  private async fetchStickerGroup(): Promise<string> {
    const requestHandle = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'application/json, text/plain, */*',
          'User-Agent': ZHIHU_USER_AGENT
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: EMOJI_CONNECT_TIMEOUT_MS,
        readTimeout: EMOJI_READ_TIMEOUT_MS,
        maxLimit: EMOJI_RESPONSE_LIMIT_BYTES,
        usingCache: false
      };
      const response = await requestHandle.request(EMOJI_STICKER_API_URL, options);
      if (Number(response.responseCode) !== 200 || typeof response.result !== 'string') {
        throw new Error(`Emoji API HTTP ${response.responseCode}`);
      }
      return response.result;
    } finally {
      requestHandle.destroy();
    }
  }

  private async writeStickerImage(directory: string, sticker: EmojiSticker): Promise<string | undefined> {
    const bytes = decodeStickerDataUrl(sticker.staticImageUrl);
    if (bytes === undefined) {
      return undefined;
    }
    const path = `${directory}/${emojiFileName(sticker.id)}`;
    const file = await fileIo.open(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE |
      fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, bytes.buffer as ArrayBuffer);
    } finally {
      await fileIo.close(file);
    }
    return path;
  }

  private rebuildPlaceholders(): void {
    this.placeholderList = Object.keys(this.mapping);
  }

  private broadcast(): void {
    AppStorage.setOrCreate<number>('emojiCatalogVersion', this.catalogVersion);
  }
}

/** 应用级单例，UI 层直接读取占位符映射。 */
export const emojiStore: EmojiStore = EmojiStore.getInstance();
