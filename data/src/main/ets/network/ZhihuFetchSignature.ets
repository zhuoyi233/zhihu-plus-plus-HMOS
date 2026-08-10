import { md5Hex } from './Md5';
import { encryptZseV4 } from './ZseSigner';

export const ZHIHU_WEB_ZSE93 = '101_3_3.0';

function requestPath(url: string): string {
  const schemeIndex = url.indexOf('//');
  const authorityAndPath = schemeIndex >= 0 ? url.substring(schemeIndex + 2) : url;
  const pathIndex = authorityAndPath.indexOf('/');
  const path = pathIndex >= 0 ? authorityAndPath.substring(pathIndex + 1) : authorityAndPath;
  return `/${path}`;
}

export function createZse96Header(
  url: string,
  dc0: string,
  body?: string,
  zse93: string = ZHIHU_WEB_ZSE93
): string {
  let source = `${zse93}+${requestPath(url)}+${dc0}`;
  if (body !== undefined) {
    source += `+${body}`;
  }
  return `2.0_${encryptZseV4(md5Hex(source))}`;
}
