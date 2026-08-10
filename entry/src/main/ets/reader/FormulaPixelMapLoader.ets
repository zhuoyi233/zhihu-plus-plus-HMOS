import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { isTrustedFormulaUrl } from './FormulaSourcePolicy';

const MAX_SVG_BYTES = 1024 * 1024;
const MAX_CACHE_ENTRIES = 64;
const MAX_CACHE_BYTES = 4 * 1024 * 1024;
const CONNECT_TIMEOUT_MS = 10000;
const READ_TIMEOUT_MS = 15000;
const svgBytesCache: Map<string, ArrayBuffer> = new Map();
const inFlightDownloads: Map<string, Promise<ArrayBuffer>> = new Map();
let cachedByteCount: number = 0;
let cacheGeneration: number = 0;

function isSvgResponse(contentType: string, bytes: ArrayBuffer): boolean {
  if (!contentType.toLowerCase().startsWith('image/svg+xml')) {
    return false;
  }
  const prefixLength = Math.min(256, bytes.byteLength);
  const prefix = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(bytes.slice(0, prefixLength)));
  return /^\uFEFF?\s*(?:<\?xml[^>]*>\s*)?<svg(?:\s|>)/i.test(prefix);
}

function normalizeZhihuSvg(bytes: ArrayBuffer): ArrayBuffer {
  let svg = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(bytes));
  const width = /\bwidth="([0-9.]+)ex"/i.exec(svg);
  const height = /\bheight="([0-9.]+)ex"/i.exec(svg);
  if (width !== null) {
    const pixels = Math.max(1, Math.ceil(Number(width[1]) * 15));
    svg = svg.replace(width[0], `width="${pixels}px"`);
  }
  if (height !== null) {
    const pixels = Math.max(1, Math.ceil(Number(height[1]) * 15));
    svg = svg.replace(height[0], `height="${pixels}px"`);
  }
  svg = svg.replace(/currentColor/g, '#000000');
  return util.TextEncoder.create('utf-8').encodeInto(svg).buffer;
}

function cacheSvg(url: string, bytes: ArrayBuffer): void {
  const stored = bytes.slice(0);
  while (svgBytesCache.size >= MAX_CACHE_ENTRIES || cachedByteCount + stored.byteLength > MAX_CACHE_BYTES) {
    const oldest = svgBytesCache.keys().next();
    if (oldest.done === true) {
      break;
    }
    const evicted = svgBytesCache.get(oldest.value);
    svgBytesCache.delete(oldest.value);
    cachedByteCount -= evicted?.byteLength ?? 0;
  }
  if (stored.byteLength <= MAX_CACHE_BYTES) {
    svgBytesCache.set(url, stored);
    cachedByteCount += stored.byteLength;
  }
}

async function downloadSvg(url: string): Promise<ArrayBuffer> {
  if (!isTrustedFormulaUrl(url)) {
    throw new Error('公式地址不在允许列表中');
  }

  let request: http.HttpRequest | undefined = undefined;
  try {
    request = http.createHttp();
    const response = await request.request(url, {
      method: http.RequestMethod.GET,
      header: { 'Accept': 'image/svg+xml' },
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: READ_TIMEOUT_MS,
      usingCache: false,
      maxLimit: MAX_SVG_BYTES,
      maxRedirects: 0
    });
    if (Number(response.responseCode) !== 200) {
      throw new Error(`公式请求失败：HTTP ${response.responseCode}`);
    }
    if (!(response.result instanceof ArrayBuffer)) {
      throw new Error('公式响应不是二进制数据');
    }
    if (response.result.byteLength === 0 || response.result.byteLength > MAX_SVG_BYTES) {
      throw new Error('公式响应大小不合法');
    }
    const headers = response.header as Record<string, string>;
    const contentType = headers['content-type'] ?? headers['Content-Type'] ?? '';
    if (!isSvgResponse(contentType, response.result)) {
      throw new Error('公式响应不是有效 SVG');
    }
    return response.result;
  } catch (error) {
    throw error instanceof Error ? error : new Error('公式下载失败');
  } finally {
    request?.destroy();
  }
}

async function cachedSvg(url: string): Promise<ArrayBuffer> {
  const cached = svgBytesCache.get(url);
  if (cached !== undefined) {
    svgBytesCache.delete(url);
    svgBytesCache.set(url, cached);
    return cached.slice(0);
  }
  const existing = inFlightDownloads.get(url);
  if (existing !== undefined) {
    return (await existing).slice(0);
  }
  const pending = downloadSvg(url);
  const generation = cacheGeneration;
  inFlightDownloads.set(url, pending);
  try {
    const bytes = await pending;
    if (generation === cacheGeneration) {
      cacheSvg(url, bytes);
    }
    return bytes.slice(0);
  } finally {
    if (inFlightDownloads.get(url) === pending) {
      inFlightDownloads.delete(url);
    }
  }
}

export function clearFormulaByteCache(): void {
  cacheGeneration += 1;
  svgBytesCache.clear();
  cachedByteCount = 0;
}

export async function loadFormulaPixelMap(url: string): Promise<image.PixelMap> {
  const bytes = await cachedSvg(url);
  const normalizedBytes = normalizeZhihuSvg(bytes);
  let source: image.ImageSource | undefined = undefined;
  try {
    // Give every decoder its own buffer because identical formulas may become visible concurrently.
    source = image.createImageSource(normalizedBytes.slice(0));
    const info = await source.getImageInfo();
    if (info.size.width <= 0 || info.size.height <= 0 || info.size.width > 4096 || info.size.height > 4096) {
      throw new Error('公式 SVG 尺寸不合法');
    }
    return await source.createPixelMap({
      editable: false
    });
  } catch (error) {
    if (error instanceof Error) {
      throw error;
    }
    const code = (error as BusinessError).code;
    const details = JSON.stringify(error);
    if (code !== undefined) {
      throw new Error(`公式 SVG 解码失败（ImageKit ${code}）`);
    }
    throw new Error(details === undefined || details.length === 0
      ? '公式 SVG 解码失败'
      : `公式 SVG 解码失败（${details.slice(0, 80)}）`);
  } finally {
    if (source !== undefined) {
      await source.release();
    }
  }
}
