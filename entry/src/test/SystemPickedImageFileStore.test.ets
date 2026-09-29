import { describe, expect, it } from '@ohos/hypium';
import {
  buildControlledImageTemporaryPath,
  isControlledImageTemporaryPath,
  isPickedMediaUri,
  shouldPurgeControlledImageTemporaryArtifact
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

    it('buildsAndRecognizesOnlyCurrentPickedImagesPaths', 0, () => {
      const path = buildControlledImageTemporaryPath(CACHE_DIR, FILE_NAME);
      expect(path).assertEqual(`${CACHE_DIR}/picked-images/${FILE_NAME}`);
      expect(isControlledImageTemporaryPath(CACHE_DIR, path)).assertTrue();
      // 阶段目录兼容层已退役：旧目录路径不再被识别为受控路径。
      expect(isControlledImageTemporaryPath(CACHE_DIR, `${CACHE_DIR}/p4-images/${FILE_NAME}`)).assertFalse();
      expect(isControlledImageTemporaryPath(CACHE_DIR, `${CACHE_DIR}/picked-images/user-name.png`)).assertFalse();
      expect(isControlledImageTemporaryPath(CACHE_DIR, '/data/storage/el2/base/files/picked-images/' + FILE_NAME))
        .assertFalse();
    });

    it('purgesOnlyExpiredAppGeneratedFinalOrInterruptedCacheArtifacts', 0, () => {
      const expiryNow: number = 1770000000000;
      const expiredSeconds: number = 1769913600;
      const freshSeconds: number = 1769913601;
      expect(shouldPurgeControlledImageTemporaryArtifact(FILE_NAME, expiredSeconds, expiryNow)).assertTrue();
      expect(shouldPurgeControlledImageTemporaryArtifact(FILE_NAME + '.copying', expiredSeconds, expiryNow)).assertTrue();
      expect(shouldPurgeControlledImageTemporaryArtifact(FILE_NAME, freshSeconds, expiryNow)).assertFalse();
      expect(shouldPurgeControlledImageTemporaryArtifact('user-name.png', expiredSeconds, expiryNow)).assertFalse();
      expect(shouldPurgeControlledImageTemporaryArtifact('../' + FILE_NAME, expiredSeconds, expiryNow)).assertFalse();
    });
  });
}
