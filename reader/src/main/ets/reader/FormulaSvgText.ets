/** MathJax 的非拉丁文字使用 SVG text，ImageKit 不绘制该节点，需在栅格上补绘。 */
export interface FormulaSvgTextRun {
  text: string;
  fontSize: number;
  /** SVG 仿射矩阵 [a, b, c, d, e, f]，已包含 viewBox 到栅格的映射。 */
  matrix: Array<number>;
}

interface SvgFrame {
  name: string;
  matrix: Array<number>;
  fontSize: number;
  hidden: boolean;
  content: string;
}

function multiply(left: Array<number>, right: Array<number>): Array<number> {
  return [left[0] * right[0] + left[2] * right[1],
    left[1] * right[0] + left[3] * right[1],
    left[0] * right[2] + left[2] * right[3],
    left[1] * right[2] + left[3] * right[3],
    left[0] * right[4] + left[2] * right[5] + left[4],
    left[1] * right[4] + left[3] * right[5] + left[5]];
}

function attribute(tag: string, name: string): string {
  const match = new RegExp(`\\s${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)')`, 'i').exec(tag);
  return match === null ? '' : match[1] ?? match[2] ?? '';
}

function numbers(value: string): Array<number> {
  const parts = value.trim().split(/[\s,]+/);
  const result = parts.map((part: string): number => Number(part));
  if (value.trim().length === 0 || result.some((part: number): boolean => !Number.isFinite(part))) {
    throw new Error('公式 SVG 文本坐标不合法');
  }
  return result;
}

/** MathJax 输出的文字变换仅使用 matrix / translate / scale；其他格式回退 TeX。 */
function transform(value: string): Array<number> {
  let result = [1, 0, 0, 1, 0, 0];
  const pattern = /(matrix|translate|scale)\s*\(([^)]*)\)/g;
  let consumed = 0;
  let match = pattern.exec(value);
  while (match !== null) {
    if (value.slice(consumed, match.index).trim().length > 0) {
      throw new Error('公式 SVG 文本变换暂不支持');
    }
    const values = numbers(match[2]);
    let next: Array<number>;
    if (match[1] === 'matrix' && values.length === 6) {
      next = values;
    } else if (match[1] === 'translate' && values.length <= 2) {
      next = [1, 0, 0, 1, values[0], values[1] ?? 0];
    } else if (match[1] === 'scale' && values.length <= 2) {
      next = [values[0], 0, 0, values[1] ?? values[0], 0, 0];
    } else {
      throw new Error('公式 SVG 文本变换不合法');
    }
    result = multiply(result, next);
    consumed = pattern.lastIndex;
    match = pattern.exec(value);
  }
  if (value.slice(consumed).trim().length > 0) {
    throw new Error('公式 SVG 文本变换暂不支持');
  }
  return result;
}

function decodeText(value: string): string {
  return value.replace(/&#(x[0-9a-f]+|[0-9]+);/gi, (_entity: string, code: string): string => {
    const point = code.charAt(0).toLowerCase() === 'x' ? parseInt(code.slice(1), 16) : Number(code);
    return point > 0 && point <= 0x10FFFF && !(point >= 0xD800 && point <= 0xDFFF)
      ? String.fromCodePoint(point) : '';
  }).replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'").replace(/&amp;/g, '&');
}

/**
 * 只提取 MathJax 的简单 text 节点，不做通用 SVG 排版。遇到 tspan 等未覆盖形式时
 * 显式失败，交给既有 TeX 兜底，避免把缺字的图片误判为成功。
 */
export function formulaSvgTextRuns(svg: string, rasterWidth: number, rasterHeight: number): Array<FormulaSvgTextRun> {
  if (!/<text\b/i.test(svg)) {
    return [];
  }
  const root = /<svg\b[^>]*>/i.exec(svg);
  const viewBox = numbers(root === null ? '' : attribute(root[0], 'viewBox'));
  if (viewBox.length !== 4 || viewBox[2] <= 0 || viewBox[3] <= 0 || rasterWidth <= 0 || rasterHeight <= 0) {
    throw new Error('公式 SVG 文本视口不合法');
  }
  const scale = Math.min(rasterWidth / viewBox[2], rasterHeight / viewBox[3]);
  const viewport = [scale, 0, 0, scale,
    (rasterWidth - viewBox[2] * scale) / 2 - viewBox[0] * scale,
    (rasterHeight - viewBox[3] * scale) / 2 - viewBox[1] * scale];
  const stack: Array<SvgFrame> = [];
  const result: Array<FormulaSvgTextRun> = [];
  // MathJax 生成的属性不含未转义尖括号；带引号的属性仍作为完整 token 处理。
  const tokens = svg.match(/<(?:"[^"]*"|'[^']*'|[^'">])*>|[^<]+/g) ?? [];
  for (const token of tokens) {
    const tag = /^<(\/?)([a-z][\w:-]*)\b/i.exec(token);
    if (tag === null) {
      const frame = stack[stack.length - 1];
      if (frame?.name === 'text') {
        frame.content += token;
      }
      continue;
    }
    const name = tag[2].toLowerCase();
    if (tag[1] === '/') {
      const frame = stack.pop();
      if (frame?.name !== name) {
        throw new Error('公式 SVG 文本结构不合法');
      }
      if (name === 'text' && !frame.hidden) {
        result.push({ text: decodeText(frame.content), fontSize: frame.fontSize, matrix: frame.matrix });
      }
      continue;
    }
    const parent = stack[stack.length - 1];
    if (name === 'tspan' || parent?.name === 'text' || (name === 'svg' && stack.length > 0)) {
      throw new Error('公式 SVG 文本布局暂不支持');
    }
    const explicitSize = attribute(token, 'font-size') ||
      /(?:^|;)\s*font-size\s*:\s*([0-9.]+)(?:px)?\s*(?:;|$)/i.exec(attribute(token, 'style'))?.[1] || '';
    const fontSize = explicitSize.length > 0 ? Number(explicitSize.replace(/px$/, '')) : parent?.fontSize ?? 16;
    if (!(fontSize > 0) || !Number.isFinite(fontSize)) {
      throw new Error('公式 SVG 文本字号不合法');
    }
    let matrix = multiply(parent?.matrix ?? viewport, transform(attribute(token, 'transform')));
    if (name === 'text') {
      matrix = multiply(matrix, [1, 0, 0, 1,
        numbers(attribute(token, 'x') || '0')[0], numbers(attribute(token, 'y') || '0')[0]]);
    }
    const frame: SvgFrame = { name: name, matrix: matrix, fontSize: fontSize,
      hidden: parent?.hidden === true || name === 'defs', content: '' };
    if (!/\/\s*>$/.test(token)) {
      stack.push(frame);
    }
  }
  if (stack.length > 0) {
    throw new Error('公式 SVG 文本结构不完整');
  }
  return result;
}
