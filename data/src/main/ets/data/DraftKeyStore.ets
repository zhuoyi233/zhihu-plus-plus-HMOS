import { util } from '@kit.ArkTS';
import { asset } from '@kit.AssetStoreKit';
import { generateDraftEncryptionKey } from './DraftCipher';
import { utf8Encode } from '../network/Utf8';

/** 与 Cookie Session key 完全独立，避免跨用途解密或清理。 */
export const DRAFT_KEY_ALIAS: string = 'zhihu-plus-content-draft-key-v1';
const ASSET_NOT_FOUND: number = 24000002;

function encodeUtf8(value: string): Uint8Array {
  return new Uint8Array(utf8Encode(value));
}

function keyQuery(): asset.AssetMap {
  const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
  query.set(asset.Tag.ALIAS, encodeUtf8(DRAFT_KEY_ALIAS));
  return query;
}

export class DraftKeyStore {
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
    } catch (_error) {
      return undefined;
    }
  }

  async getOrCreate(): Promise<Uint8Array> {
    const existing = await this.load();
    if (existing !== undefined) {
      return existing;
    }
    const keyData = generateDraftEncryptionKey();
    const attributes = keyQuery();
    attributes.set(asset.Tag.SECRET, keyData);
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
    attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    try {
      await asset.add(attributes);
      return keyData;
    } catch (_error) {
      keyData.fill(0);
      throw new Error('Draft key Asset Store add failed');
    }
  }

  async clear(): Promise<void> {
    try {
      await asset.remove(keyQuery());
    } catch (error) {
      if (!isAssetNotFound(error)) {
        throw new Error('Draft key Asset Store removal failed');
      }
    }
  }
}

function isAssetNotFound(error: Object): boolean {
  return error instanceof Error && error.message.includes(`${ASSET_NOT_FOUND}`);
}
