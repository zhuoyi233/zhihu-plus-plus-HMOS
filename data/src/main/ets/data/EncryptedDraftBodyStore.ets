import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { decryptDraftHtml, encryptDraftHtml } from './DraftCipher';
import { DraftKeyStore } from './DraftKeyStore';

const DRAFT_DIRECTORY: string = 'content-drafts-v1';

export interface DraftBodyStore {
  save(draftKey: string, html: string): Promise<void>;
  load(draftKey: string): Promise<string | undefined>;
  remove(draftKey: string): Promise<void>;
}

/**
 * 正文仅写入 filesDir 下的 AES-GCM 信封。临时文件写完、关闭后才以 moveFile 覆盖目标。
 * 路径只由已验证的草稿键生成，调用方不能传入任意文件路径。
 */
export class EncryptedDraftBodyStore implements DraftBodyStore {
  private readonly directory: string;
  private readonly keyStore: DraftKeyStore;

  constructor(context: common.Context, keyStore: DraftKeyStore = new DraftKeyStore()) {
    this.directory = `${context.filesDir}/${DRAFT_DIRECTORY}`;
    this.keyStore = keyStore;
  }

  async save(draftKey: string, html: string): Promise<void> {
    const path = this.pathFor(draftKey);
    const temporaryPath = `${path}.tmp`;
    let keyData: Uint8Array | undefined;
    try {
      await this.ensureDirectory();
      keyData = await this.keyStore.getOrCreate();
      const encrypted = await encryptDraftHtml(html, keyData);
      await this.writeTemporaryFile(temporaryPath, encrypted);
      await fileIo.moveFile(temporaryPath, path, 0);
    } catch (_error) {
      await this.removeIfPresent(temporaryPath);
      throw new Error('Encrypted draft save failed');
    } finally {
      keyData?.fill(0);
    }
  }

  async load(draftKey: string): Promise<string | undefined> {
    const path = this.pathFor(draftKey);
    if (!(await fileIo.access(path))) {
      return undefined;
    }
    let keyData: Uint8Array | undefined;
    try {
      const encrypted = await fileIo.readText(path);
      keyData = await this.keyStore.load();
      if (keyData === undefined) {
        throw new Error('missing key');
      }
      return await decryptDraftHtml(encrypted, keyData);
    } catch (_error) {
      throw new Error('Encrypted draft load failed');
    } finally {
      keyData?.fill(0);
    }
  }

  async remove(draftKey: string): Promise<void> {
    await this.removeIfPresent(this.pathFor(draftKey));
  }

  private pathFor(draftKey: string): string {
    if (!/^(?:answer|pin):sha256:[0-9a-f]{64}:(?:[0-9]{1,30}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/.test(draftKey)) {
      throw new Error('Draft body key is invalid');
    }
    return `${this.directory}/${draftKey.replace(/:/g, '_')}.enc`;
  }

  private async ensureDirectory(): Promise<void> {
    try {
      await fileIo.mkdir(this.directory, true);
    } catch (_error) {
      if (!(await fileIo.access(this.directory))) {
        throw new Error('Draft directory creation failed');
      }
    }
  }

  private async writeTemporaryFile(path: string, content: string): Promise<void> {
    const file = await fileIo.open(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE |
      fileIo.OpenMode.TRUNC | fileIo.OpenMode.SYNC);
    try {
      const written = await fileIo.write(file.fd, content);
      if (written !== content.length) {
        throw new Error('partial write');
      }
    } finally {
      await fileIo.close(file);
    }
  }

  private async removeIfPresent(path: string): Promise<void> {
    try {
      if (await fileIo.access(path)) {
        await fileIo.unlink(path);
      }
    } catch (_error) {
      throw new Error('Encrypted draft removal failed');
    }
  }
}
