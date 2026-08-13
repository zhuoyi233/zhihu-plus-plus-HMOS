import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { JsonNumberValue, JsonObjectValue, JsonStringValue, parseStrictJson } from 'core';

const TRANSFORMATION = 'AES256|GCM|PKCS7';
const KEY_ALGORITHM = 'AES256';
const AAD = 'com.github.zhuoyi233.zhplus:cookie-session:v1';

class CipherEnvelope {
  readonly version: number;
  readonly iv: string;
  readonly cipherText: string;
  readonly authTag: string;

  constructor(version: number, iv: string, cipherText: string, authTag: string) {
    this.version = version;
    this.iv = iv;
    this.cipherText = cipherText;
    this.authTag = authTag;
  }
}

function encodeUtf8(value: string): Uint8Array {
  return util.TextEncoder.create('utf-8').encodeInto(value);
}

function decodeUtf8(value: Uint8Array): string {
  return util.TextDecoder.create('utf-8').decodeToString(value);
}

function encodeBase64(value: Uint8Array): string {
  return new util.Base64Helper().encodeToStringSync(value);
}

function decodeBase64(value: string): Uint8Array {
  return new util.Base64Helper().decodeSync(value);
}

function createParams(iv: Uint8Array, authTag: Uint8Array): cryptoFramework.GcmParamsSpec {
  return {
    iv: { data: iv },
    aad: { data: encodeUtf8(AAD) },
    authTag: { data: authTag },
    algName: 'GcmParamsSpec'
  };
}

function createSymKey(keyData: Uint8Array): cryptoFramework.SymKey {
  try {
    return cryptoFramework.createSymKeyGenerator(KEY_ALGORITHM).convertKeySync({ data: keyData });
  } catch (_error) {
    throw new Error('Session key conversion failed');
  }
}

export function generateSessionKey(): Uint8Array {
  let key: cryptoFramework.SymKey | undefined;
  try {
    key = cryptoFramework.createSymKeyGenerator(KEY_ALGORITHM).generateSymKeySync();
    return new Uint8Array(key.getEncoded().data);
  } catch (_error) {
    throw new Error('Session key generation failed');
  } finally {
    key?.clearMem();
  }
}

export async function encryptSession(plainText: string, keyData: Uint8Array): Promise<string> {
  let key: cryptoFramework.SymKey | undefined;
  try {
    key = createSymKey(keyData);
    const iv = cryptoFramework.createRandom().generateRandomSync(12).data;
    const params = createParams(iv, new Uint8Array(16));
    const cipher = cryptoFramework.createCipher(TRANSFORMATION);
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, key, params);
    const cipherText = await cipher.update({ data: encodeUtf8(plainText) });
    const authTag = await cipher.doFinal(null);
    const envelope = new CipherEnvelope(1, encodeBase64(iv), encodeBase64(cipherText.data),
      encodeBase64(authTag.data));
    return JSON.stringify(envelope);
  } catch (_error) {
    throw new Error('Session encryption failed');
  } finally {
    key?.clearMem();
  }
}

export async function decryptSession(serialized: string, keyData: Uint8Array): Promise<string> {
  const envelope = parseStrictJson(serialized);
  if (!(envelope instanceof JsonObjectValue)) {
    throw new Error('Unsupported encrypted session format');
  }
  const version = envelope.get('version');
  const iv = envelope.get('iv');
  const authTag = envelope.get('authTag');
  const cipherText = envelope.get('cipherText');
  if (!(version instanceof JsonNumberValue) || version.value !== 1 ||
    !(iv instanceof JsonStringValue) || !(authTag instanceof JsonStringValue) ||
    !(cipherText instanceof JsonStringValue)) {
    throw new Error('Unsupported encrypted session format');
  }

  let key: cryptoFramework.SymKey | undefined;
  try {
    key = createSymKey(keyData);
    const params = createParams(decodeBase64(iv.value), decodeBase64(authTag.value));
    const cipher = cryptoFramework.createCipher(TRANSFORMATION);
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, key, params);
    const plainText = await cipher.update({ data: decodeBase64(cipherText.value) });
    await cipher.doFinal(null);
    return decodeUtf8(plainText.data);
  } catch (_error) {
    throw new Error('Session decryption failed');
  } finally {
    key?.clearMem();
  }
}
