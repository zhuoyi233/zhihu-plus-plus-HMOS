import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { asset } from '@kit.AssetStoreKit';
import { generateSessionKey } from './SessionCipher';

const KEY_ALIAS = 'zhihu-plus-cookie-session-key-v1';
const ASSET_NOT_FOUND = 24000002;

function encodeUtf8(value: string): Uint8Array {
  return util.TextEncoder.create('utf-8').encodeInto(value);
}

function keyQuery(): asset.AssetMap {
  const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
  query.set(asset.Tag.ALIAS, encodeUtf8(KEY_ALIAS));
  return query;
}

export class SessionKeyStore {
  async load(): Promise<Uint8Array | undefined> {
    const query = keyQuery();
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const results = await asset.query(query);
      if (results.length !== 1) {
        return undefined;
      }
      const secret = results[0].get(asset.Tag.SECRET);
      return secret instanceof Uint8Array ? secret : undefined;
    } catch (error) {
      const businessError = error as BusinessError;
      if (businessError.code === ASSET_NOT_FOUND) {
        return undefined;
      }
      throw new Error(`Asset Store query failed (${businessError.code}): ${businessError.message}`);
    }
  }

  async getOrCreate(): Promise<Uint8Array> {
    const existing = await this.load();
    if (existing !== undefined) {
      return existing;
    }

    const keyData = generateSessionKey();
    const attributes = keyQuery();
    attributes.set(asset.Tag.SECRET, keyData);
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
    attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    try {
      await asset.add(attributes);
      return keyData;
    } catch (error) {
      keyData.fill(0);
      const businessError = error as BusinessError;
      throw new Error(`Asset Store add failed (${businessError.code})`);
    }
  }

  async clear(): Promise<void> {
    try {
      await asset.remove(keyQuery());
    } catch (error) {
      const businessError = error as BusinessError;
      if (businessError.code !== ASSET_NOT_FOUND) {
        throw new Error(`Asset Store remove failed (${businessError.code}): ${businessError.message}`);
      }
    }
  }
}
