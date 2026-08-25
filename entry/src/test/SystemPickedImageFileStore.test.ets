import { describe, expect, it } from '@ohos/hypium';
import {
  buildControlledImageTemporaryPath,
  isControlledImageTemporaryPath,
  isPickedMediaUri
} from '../main/ets/platform/SystemPickedImageFileStore';

const CACHE_DIR: string = '/data/storage/el2/base/cache';
const FILE_NAME: string = '0123456789abcdef0123456789abcdef.png';

export default function systemPickedImageFileStoreTest(): void {
  describe('systemPickedImageFileStoreTest', () => {
    it('acceptsOnlyKnownPickerMediaUrisWithoutTraversalOrWhitespace', 0, () => {
      expect(isPickedMediaUri('file://media/Photo/1/IMG_0001.png')).assertTrue();
      expect(isPickedMediaUri('file://com.ohos.filemanager.dir/Photo/1/IMG_0001.png')).assertTrue();
      expect(isPickedMediaUri('file://media/Photo/1/../private.png')).assertFalse();
      expect(isPickedMediaUri('https://media/Photo/1/IMG_0001.png')).assertFalse();
      expect(isPickedMediaUri('file://media/Photo/1/file name.png')).assertFalse();
    });

    it('buildsAndRecognizesOnlyAppGeneratedCacheImagePaths', 0, () => {
      const path = buildControlledImageTemporaryPath(CACHE_DIR, FILE_NAME);
      expect(path).assertEqual(`${CACHE_DIR}/p4-images/${FILE_NAME}`);
      expect(isControlledImageTemporaryPath(CACHE_DIR, path)).assertTrue();
      expect(isControlledImageTemporaryPath(CACHE_DIR, `${CACHE_DIR}/p4-images/user-name.png`)).assertFalse();
      expect(isControlledImageTemporaryPath(CACHE_DIR, '/data/storage/el2/base/files/p4-images/' + FILE_NAME)).assertFalse();
    });
  });
}
