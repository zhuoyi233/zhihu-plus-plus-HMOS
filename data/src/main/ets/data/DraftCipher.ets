import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { JsonNumberValue, JsonObjectValue, JsonStringValue, parseStrictJson } from 'core';
import { utf8Encode } from '../network/Utf8';

const TRANSFORMATION: string = 'AES256|GCM|PKCS7';
const KEY_ALGORITHM: string = 'AES256';
const DRAFT_AAD: string = 'com.github.zhuoyi233.zhplus:content-draft:v1';

class DraftCipherEnvelope {
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

export function generateDraftEncryptionKey(): Uint8Array {
  let key: cryptoFramework.SymKey | undefined;
  try {
    key = cryptoFramework.createSymKeyGenerator(KEY_ALGORITHM).generateSymKeySync();
    return new Uint8Array(key.getEncoded().data);
  } catch (_error) {
    throw new Error('Draft encryption key generation failed');
  } finally {
    key?.clearMem();
  }
}

export async function encryptDraftHtml(plainText: string, keyData: Uint8Array): Promise<string> {
  let key: cryptoFramework.SymKey | undefined;
  try {
    key = createSymKey(keyData);
    const iv = cryptoFramework.createRandom().generateRandomSync(12).data;
    const cipher = cryptoFramework.createCipher(TRANSFORMATION);
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, key, createParams(iv, new Uint8Array(16)));
    const cipherText = await cipher.update({ data: new Uint8Array(utf8Encode(plainText)) });
    const authTag = await cipher.doFinal(null);
    return JSON.stringify(new DraftCipherEnvelope(1, encodeBase64(iv), encodeBase64(cipherText.data),
      encodeBase64(authTag.data)));
  } catch (_error) {
    throw new Error('Draft encryption failed');
  } finally {
    key?.clearMem();
  }
}

export async function decryptDraftHtml(serialized: string, keyData: Uint8Array): Promise<string> {
  const envelope = decodeEnvelope(serialized);
  let key: cryptoFramework.SymKey | undefined;
  try {
    key = createSymKey(keyData);
    const cipher = cryptoFramework.createCipher(TRANSFORMATION);
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, key,
      createParams(decodeBase64(envelope.iv), decodeBase64(envelope.authTag)));
    const plainText = await cipher.update({ data: decodeBase64(envelope.cipherText) });
    await cipher.doFinal(null);
    return new util.TextDecoder('utf-8').decodeToString(plainText.data);
  } catch (_error) {
    throw new Error('Draft decryption failed');
  } finally {
    key?.clearMem();
  }
}

function decodeEnvelope(serialized: string): DraftCipherEnvelope {
  let parsed: JsonObjectValue;
  try {
    const value = parseStrictJson(serialized);
    if (!(value instanceof JsonObjectValue)) {
      throw new Error('invalid');
    }
    parsed = value;
  } catch (_error) {
    throw new Error('Unsupported encrypted draft format');
  }
  const version = parsed.get('version');
  const iv = parsed.get('iv');
  const authTag = parsed.get('authTag');
  const cipherText = parsed.get('cipherText');
  if (!(version instanceof JsonNumberValue) || version.value !== 1 ||
    !(iv instanceof JsonStringValue) || !(authTag instanceof JsonStringValue) ||
    !(cipherText instanceof JsonStringValue)) {
    throw new Error('Unsupported encrypted draft format');
  }
  return new DraftCipherEnvelope(version.value, iv.value, cipherText.value, authTag.value);
}

function createSymKey(keyData: Uint8Array): cryptoFramework.SymKey {
  try {
    return cryptoFramework.createSymKeyGenerator(KEY_ALGORITHM).convertKeySync({ data: keyData });
  } catch (_error) {
    throw new Error('Draft encryption key conversion failed');
  }
}

function createParams(iv: Uint8Array, authTag: Uint8Array): cryptoFramework.GcmParamsSpec {
  return {
    iv: { data: iv },
    aad: { data: new Uint8Array(utf8Encode(DRAFT_AAD)) },
    authTag: { data: authTag },
    algName: 'GcmParamsSpec'
  };
}

function encodeBase64(value: Uint8Array): string {
  return new util.Base64Helper().encodeToStringSync(value);
}

function decodeBase64(value: string): Uint8Array {
  return new util.Base64Helper().decodeSync(value);
}
