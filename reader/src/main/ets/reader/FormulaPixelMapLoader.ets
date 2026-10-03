import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import {
  FORMULA_FALLBACK_PIXELS_PER_EX,
  FormulaDisplaySize,
  formulaDecodePixelsPerEx,
  formulaSvgExSize,
  isMathJaxErrorSvg,
  normalizeFormulaSvgText
} from './FormulaRendering';
import { isTrustedFormulaUrl } from './FormulaSourcePolicy';

const MAX_SVG_BYTES = 1024 * 1024;
const MAX_CACHE_ENTRIES = 64;
const MAX_CACHE_BYTES = 4 * 1024 * 1024;
const CONNECT_TIMEOUT_MS = 10000;
const READ_TIMEOUT_MS = 15000;
// 知乎 equation 端点会按请求指纹做风控：无 UA 或纯游客请求可能被 302 重定向到
// unhuman 验证页。与登录请求保持一致地携带桌面 UA，并在应用已登录时带上会话
// Cookie（含 z_c0），才能稳定取回公式 SVG。
const FORMULA_USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36';

/** 公式解码结果：除 PixelMap 外带回 ex 固有尺寸与实际采样密度，供显示尺寸换算。 */
export interface FormulaPixelMapResult {
  pixelMap: image.PixelMap;
  /** 公式 SVG 固有尺寸（ex 单位，来自根节点 width/height 声明）。 */
  exSize: FormulaDisplaySize;
  /** 实际解码采样密度（px/ex）：与 formulaDecodePixelsPerEx 的钳制结果一致。 */
  pixelsPerEx: number;
}

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

async function downloadSvg(url: string, cookieHeader?: string): Promise<ArrayBuffer> {
  if (!isTrustedFormulaUrl(url)) {
    throw new Error('公式地址不在允许列表中');
  }

  const headers: Record<string, string> = {
    'Accept': 'image/svg+xml',
    'User-Agent': FORMULA_USER_AGENT
  };
  if (cookieHeader !== undefined && cookieHeader.length > 0) {
    headers['Cookie'] = cookieHeader;
  }
  let request: http.HttpRequest | undefined = undefined;
  try {
    request = http.createHttp();
    const response = await request.request(url, {
      method: http.RequestMethod.GET,
      header: headers,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: READ_TIMEOUT_MS,
      usingCache: false,
      maxLimit: MAX_SVG_BYTES,
      // 知乎 /equation 正常返回 200 image/svg+xml，不重定向；风控时 302 到 unhuman 也是 HTML 而非 SVG。
      // 手动 Cookie 头 + 跟随重定向会把 Cookie 原样转发到重定向目标，因此保持 0 关闭重定向，
      // 让 Cookie 只发往 isTrustedFormulaUrl 锁定的 www.zhihu.com/equation 这一跳。
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
    const headerText = JSON.stringify(response.header).toLowerCase();
    const contentType = headerText.includes('image/svg+xml') ? 'image/svg+xml' : '';
    if (!isSvgResponse(contentType, response.result)) {
      throw new Error('公式响应不是有效 SVG');
    }
    return response.result;
  } catch (error) {
    if (error instanceof Error) {
      throw error;
    }
    const details = JSON.stringify(error);
    throw new Error(details === undefined || details.length === 0
      ? '公式下载失败'
      : `公式下载失败（${details.slice(0, 120)}）`);
  } finally {
    request?.destroy();
  }
}

async function cachedSvg(url: string, cookieHeader?: string): Promise<ArrayBuffer> {
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
  const pending = downloadSvg(url, cookieHeader);
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

/**
 * 下载并解码公式 SVG 为 PixelMap。
 *
 * @param targetPixelsPerEx 目标解码采样密度（px/ex）：调用方按
 * 「正文字号 × 0.5em/ex × 屏幕密度」计算，使栅格与显示物理像素 1:1（issue #51
 * 的模糊问题：固定 15px/ex 采样在显示端被放大 2 倍左右）。函数内部会按公式
 * 固有尺寸钳制，保证栅格单边不超 ImageKit 限制——超长公式降采样密度而不是
 * 整条识别失败。缺省时用 15px/ex 兜底。
 */
export async function loadFormulaPixelMap(url: string, cookieHeader?: string,
  foregroundColor: string = '#111111', targetPixelsPerEx: number = FORMULA_FALLBACK_PIXELS_PER_EX):
  Promise<FormulaPixelMapResult> {
  const bytes = await cachedSvg(url, cookieHeader);
  const svg = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(bytes));
  if (isMathJaxErrorSvg(svg)) {
    // 知乎端点对无法解析的 LaTeX 仍返回 200，内容是红底红字的 MathJax 错误提示框；
    // 视为公式渲染失败，由组件退回 TeX 替代文本。
    throw new Error('公式无法被知乎公式服务解析');
  }
  const exSize = formulaSvgExSize(svg);
  const pixelsPerEx = exSize === undefined
    ? FORMULA_FALLBACK_PIXELS_PER_EX
    : formulaDecodePixelsPerEx(exSize.width, exSize.height, targetPixelsPerEx);
  const normalizedBytes = util.TextEncoder.create('utf-8')
    .encodeInto(normalizeFormulaSvgText(svg, foregroundColor, pixelsPerEx)).buffer;
  let source: image.ImageSource | undefined = undefined;
  try {
    source = image.createImageSource(normalizedBytes.slice(0));
    const info = await source.getImageInfo();
    if (info.size.width <= 0 || info.size.height <= 0 || info.size.width > 4096 || info.size.height > 4096) {
      throw new Error('公式 SVG 尺寸不合法');
    }
    const pixelMap = await source.createPixelMap({
      editable: false
    });
    const result: FormulaPixelMapResult = {
      pixelMap: pixelMap,
      exSize: exSize ?? { width: info.size.width / pixelsPerEx, height: info.size.height / pixelsPerEx },
      pixelsPerEx: pixelsPerEx
    };
    return result;
  } catch (error) {
    if (error instanceof Error) {
      throw error;
    }
    const details = JSON.stringify(error);
    const codeMatch = /"code"\s*:\s*(-?\d+)/.exec(details ?? '');
    const code = codeMatch === null ? undefined : Number(codeMatch[1]);
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
