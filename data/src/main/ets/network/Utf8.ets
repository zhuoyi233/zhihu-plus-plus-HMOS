export function utf8Encode(input: string): Array<number> {
  const output: Array<number> = [];
  for (let index = 0; index < input.length; index += 1) {
    let codePoint = input.charCodeAt(index);
    if (codePoint >= 0xd800 && codePoint <= 0xdbff) {
      const low = index + 1 < input.length ? input.charCodeAt(index + 1) : 0;
      if (low >= 0xdc00 && low <= 0xdfff) {
        codePoint = 0x10000 + ((codePoint - 0xd800) << 10) + (low - 0xdc00);
        index += 1;
      } else {
        codePoint = 0xfffd;
      }
    } else if (codePoint >= 0xdc00 && codePoint <= 0xdfff) {
      codePoint = 0xfffd;
    }

    if (codePoint <= 0x7f) {
      output.push(codePoint);
    } else if (codePoint <= 0x7ff) {
      output.push(0xc0 | (codePoint >>> 6));
      output.push(0x80 | (codePoint & 0x3f));
    } else if (codePoint <= 0xffff) {
      output.push(0xe0 | (codePoint >>> 12));
      output.push(0x80 | ((codePoint >>> 6) & 0x3f));
      output.push(0x80 | (codePoint & 0x3f));
    } else {
      output.push(0xf0 | (codePoint >>> 18));
      output.push(0x80 | ((codePoint >>> 12) & 0x3f));
      output.push(0x80 | ((codePoint >>> 6) & 0x3f));
      output.push(0x80 | (codePoint & 0x3f));
    }
  }
  return output;
}
