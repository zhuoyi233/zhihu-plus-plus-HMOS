export function isTrustedFormulaUrl(value: string): boolean {
  // An anchored authority/path/query policy keeps this check available in local unit tests,
  // where the system URL parser is only a stub, without accepting userinfo, ports or lookalike hosts.
  return /^https:\/\/www\.zhihu\.com\/equation\?tex=[^&#]+(?:&[^#]*)?(?:#.*)?$/i.test(value);
}
