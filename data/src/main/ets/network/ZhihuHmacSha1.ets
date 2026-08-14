/**
 * HMAC-SHA1（对齐上游 expect/actual hmacSha1Hex 的 Android 平台实现），
 * 返回小写十六进制串。用于手机号登录 sign_in / udid_guest 的请求签名。
 *
 * 不用 @kit.CryptoArchitectureKit：其 HMAC 密钥转换要求密钥长度等于哈希长度
 * （HMAC|SHA1 需 20 字节），而上游 secret（36/32 字节）不符合；纯 ArkTS 实现
 * 按 RFC 2104 计算，密钥长度任意（≤64 直接使用，>64 先 SHA1），结果与标准
 * HMAC-SHA1 完全一致，且 host 侧单元测试可运行。
 */

import { utf8Encode } from './Utf8';

function utf8Bytes(value: string): Uint8Array {
  return new Uint8Array(utf8Encode(value));
}

function bytesToHex(bytes: Uint8Array): string {
  let result = '';
  for (let index = 0; index < bytes.length; index += 1) {
    result += bytes[index].toString(16).padStart(2, '0');
  }
  return result;
}

function rotateLeft(value: number, shift: number): number {
  return ((value << shift) | (value >>> (32 - shift))) >>> 0;
}

/** SHA-1 摘要（纯 ArkTS，返回 20 字节）。 */
function sha1Bytes(input: Uint8Array): Uint8Array {
  const originalLength = input.length;
  const paddedLength = Math.ceil((originalLength + 9) / 64) * 64;
  const padded = new Uint8Array(paddedLength);
  padded.set(input);
  padded[originalLength] = 0x80;
  const bitLength = originalLength * 8;
  const high = Math.floor(bitLength / 0x100000000);
  const low = bitLength >>> 0;
  padded[paddedLength - 8] = (high >>> 24) & 0xff;
  padded[paddedLength - 7] = (high >>> 16) & 0xff;
  padded[paddedLength - 6] = (high >>> 8) & 0xff;
  padded[paddedLength - 5] = high & 0xff;
  padded[paddedLength - 4] = (low >>> 24) & 0xff;
  padded[paddedLength - 3] = (low >>> 16) & 0xff;
  padded[paddedLength - 2] = (low >>> 8) & 0xff;
  padded[paddedLength - 1] = low & 0xff;

  let h0 = 0x67452301;
  let h1 = 0xefcdab89;
  let h2 = 0x98badcfe;
  let h3 = 0x10325476;
  let h4 = 0xc3d2e1f0;
  const words = new Uint32Array(80);
  for (let offset = 0; offset < paddedLength; offset += 64) {
    for (let index = 0; index < 16; index += 1) {
      const base = offset + index * 4;
      words[index] = ((padded[base] << 24) | (padded[base + 1] << 16) |
        (padded[base + 2] << 8) | padded[base + 3]) >>> 0;
    }
    for (let index = 16; index < 80; index += 1) {
      words[index] = rotateLeft(words[index - 3] ^ words[index - 8] ^ words[index - 14] ^ words[index - 16], 1);
    }
    let a = h0;
    let b = h1;
    let c = h2;
    let d = h3;
    let e = h4;
    for (let index = 0; index < 80; index += 1) {
      let f: number;
      let k: number;
      if (index < 20) {
        f = (b & c) | (~b & d);
        k = 0x5a827999;
      } else if (index < 40) {
        f = b ^ c ^ d;
        k = 0x6ed9eba1;
      } else if (index < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8f1bbcdc;
      } else {
        f = b ^ c ^ d;
        k = 0xca62c1d6;
      }
      const temp = (rotateLeft(a, 5) + f + e + k + words[index]) >>> 0;
      e = d;
      d = c;
      c = rotateLeft(b, 30);
      b = a;
      a = temp;
    }
    h0 = (h0 + a) >>> 0;
    h1 = (h1 + b) >>> 0;
    h2 = (h2 + c) >>> 0;
    h3 = (h3 + d) >>> 0;
    h4 = (h4 + e) >>> 0;
  }

  const digest = new Uint8Array(20);
  digest[0] = (h0 >>> 24) & 0xff;
  digest[1] = (h0 >>> 16) & 0xff;
  digest[2] = (h0 >>> 8) & 0xff;
  digest[3] = h0 & 0xff;
  digest[4] = (h1 >>> 24) & 0xff;
  digest[5] = (h1 >>> 16) & 0xff;
  digest[6] = (h1 >>> 8) & 0xff;
  digest[7] = h1 & 0xff;
  digest[8] = (h2 >>> 24) & 0xff;
  digest[9] = (h2 >>> 16) & 0xff;
  digest[10] = (h2 >>> 8) & 0xff;
  digest[11] = h2 & 0xff;
  digest[12] = (h3 >>> 24) & 0xff;
  digest[13] = (h3 >>> 16) & 0xff;
  digest[14] = (h3 >>> 8) & 0xff;
  digest[15] = h3 & 0xff;
  digest[16] = (h4 >>> 24) & 0xff;
  digest[17] = (h4 >>> 16) & 0xff;
  digest[18] = (h4 >>> 8) & 0xff;
  digest[19] = h4 & 0xff;
  return digest;
}

/** 计算 HMAC-SHA1 并返回小写 hex（RFC 2104；密钥 ≤64 字节直接用，>64 先 SHA1）。 */
export function hmacSha1Hex(key: string, message: string): string {
  const keyBytes = utf8Bytes(key);
  const keyBlock = new Uint8Array(64);
  if (keyBytes.length > 64) {
    keyBlock.set(sha1Bytes(keyBytes));
  } else {
    keyBlock.set(keyBytes);
  }
  const ipad = new Uint8Array(64);
  const opad = new Uint8Array(64);
  for (let index = 0; index < 64; index += 1) {
    ipad[index] = keyBlock[index] ^ 0x36;
    opad[index] = keyBlock[index] ^ 0x5c;
  }
  const messageBytes = utf8Bytes(message);
  const inner = new Uint8Array(64 + messageBytes.length);
  inner.set(ipad);
  inner.set(messageBytes, 64);
  const innerHash = sha1Bytes(inner);
  const outer = new Uint8Array(64 + innerHash.length);
  outer.set(opad);
  outer.set(innerHash, 64);
  return bytesToHex(sha1Bytes(outer));
}
