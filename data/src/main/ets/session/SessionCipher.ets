import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

const TRANSFORMATION = 'AES256|GCM|PKCS7';
const KEY_ALGORITHM = 'AES256';
const AAD = 'com.github.zhuoyi233.zhplus:cookie-session:v1';

interface CipherEnvelope {
  version: number;
  iv: string;
  cipherText: string;
  authTag: string;
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
  } catch (error) {
    throw cryptoError('Session key conversion', error as BusinessError);
  }
}

function cryptoError(operation: string, error: BusinessError): Error {
  return new Error(`${operation} failed (${error.code})`);
}

export function generateSessionKey(): Uint8Array {
  let key: cryptoFramework.SymKey | undefined;
  try {
    key = cryptoFramework.createSymKeyGenerator(KEY_ALGORITHM).generateSymKeySync();
    return new Uint8Array(key.getEncoded().data);
  } catch (error) {
    throw cryptoError('Session key generation', error as BusinessError);
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
    const envelope: CipherEnvelope = {
      version: 1,
      iv: encodeBase64(iv),
      cipherText: encodeBase64(cipherText.data),
      authTag: encodeBase64(authTag.data)
    };
    return JSON.stringify(envelope);
  } catch (error) {
    throw cryptoError('Session encryption', error as BusinessError);
  } finally {
    key?.clearMem();
  }
}

export async function decryptSession(serialized: string, keyData: Uint8Array): Promise<string> {
  const envelope = JSON.parse(serialized) as CipherEnvelope;
  if (envelope.version !== 1) {
    throw new Error('Unsupported encrypted session format');
  }

  let key: cryptoFramework.SymKey | undefined;
  try {
    key = createSymKey(keyData);
    const params = createParams(decodeBase64(envelope.iv), decodeBase64(envelope.authTag));
    const cipher = cryptoFramework.createCipher(TRANSFORMATION);
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, key, params);
    const plainText = await cipher.update({ data: decodeBase64(envelope.cipherText) });
    await cipher.doFinal(null);
    return decodeUtf8(plainText.data);
  } catch (error) {
    throw cryptoError('Session decryption', error as BusinessError);
  } finally {
    key?.clearMem();
  }
}
