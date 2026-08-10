import { parseAbsoluteUrl, ParsedAbsoluteUrl } from '../navigation/AbsoluteUrlParser';

export function isTrustedFormulaUrl(value: string): boolean {
  const parsed: ParsedAbsoluteUrl | undefined = parseAbsoluteUrl(value);
  if (parsed === undefined) {
    return false;
  }
  const tex = parsed.params.get('tex');
  return parsed.protocol === 'https:' &&
    parsed.hostname === 'www.zhihu.com' &&
    parsed.port.length === 0 &&
    !parsed.hasUserInfo &&
    parsed.pathname === '/equation' &&
    tex !== undefined && tex.length > 0;
}
