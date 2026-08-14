/**
 * HMAC-SHA1（对齐上游 expect/actual hmacSha1Hex 的 Android 平台实现），
 * 返回小写十六进制串。用于手机号登录 sign_in / udid_guest 的请求签名。
 */

import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { utf8Encode } from './Utf8';

function utf8Bytes(value: string): Uint8Array {
  return new Uint8Array(utf8Encode(value));
}

function bytesToHex(bytes: Uint8Array): string {
  let result = '';
  for (let index = 0; index < bytes.length; index += 1) {
    const byte = bytes[index].toString(16).padStart(2, '0');
    result += byte;
  }
  return result;
}

/** 计算 HMAC-SHA1 并返回小写 hex。 */
export function hmacSha1Hex(key: string, message: string): string {
  const keyData: cryptoFramework.DataBlob = { data: utf8Bytes(key) };
  const generator = cryptoFramework.createSymKeyGenerator('HMAC');
  const keyObj = generator.convertKeySync(keyData);
  const macSpec: cryptoFramework.MacSpec = { algName: 'HMAC|SHA1' };
  const mac = cryptoFramework.createMac(macSpec);
  try {
    mac.initSync(keyObj);
    mac.updateSync({ data: utf8Bytes(message) });
    const result = mac.doFinalSync();
    return bytesToHex(result.data);
  } finally {
    keyObj.clearMem();
  }
}
