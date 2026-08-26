import { describe, expect, it } from '@ohos/hypium';
import {
  ImageTemporaryFile,
  ImageUploadFailureKind,
  PickedImageInspection,
  ValidatedPickedImage
} from 'data';
import { PickedImage } from '../main/ets/platform/P4PlatformServices';
import {
  defaultMediaPickerRuntimePolicy,
  MediaPickerCoordinator,
  MediaPickerPhase,
  PhotoPickerResult,
  PhotoPickerResultKind,
  PhotoPickerSelection,
  PickedImageInspector,
  PickedImageTemporaryStore,
  SystemPhotoPickerGateway
} from '../main/ets/platform/MediaPickerCoordinator';

const CACHE_DIR: string = '/data/storage/el2/base/cache';
const NOW: number = 1770000000000;
const PNG_HEADER: Array<number> = [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x03, 0x00
];

class FixedPhotoPickerGateway implements SystemPhotoPickerGateway {
  result: PhotoPickerResult;
  calls: number = 0;
  requestedMaxCount: number = 0;

  constructor(result: PhotoPickerResult) {
    this.result = result;
  }

  pickImages(maxCount: number): Promise<PhotoPickerResult> {
    this.calls += 1;
    this.requestedMaxCount = maxCount;
    return Promise.resolve(this.result);
  }
}

class DeferredPhotoPickerGateway implements SystemPhotoPickerGateway {
  private resolveResult?: (result: PhotoPickerResult) => void;

  pickImages(_maxCount: number): Promise<PhotoPickerResult> {
    return new Promise<PhotoPickerResult>((resolve: (result: PhotoPickerResult) => void): void => {
      this.resolveResult = resolve;
    });
  }

  resolve(result: PhotoPickerResult): void {
    const resolver = this.resolveResult;
    if (resolver !== undefined) {
      resolver(result);
    }
  }
}

class FakePickedImageInspector implements PickedImageInspector {
  readonly inspections: Map<string, PickedImageInspection> = new Map<string, PickedImageInspection>();
  calls: number = 0;

  inspect(selection: PhotoPickerSelection): Promise<PickedImageInspection> {
    this.calls += 1;
    const inspected = this.inspections.get(selection.image.uri);
    if (inspected === undefined) {
      return Promise.reject(new Error('missing image fixture'));
    }
    return Promise.resolve(inspected);
  }
}

class MemoryTemporaryStore implements PickedImageTemporaryStore {
  readonly written: Array<ImageTemporaryFile> = [];
  readonly removed: Array<string> = [];
  failWrite: boolean = false;

  write(_selection: PhotoPickerSelection, image: ValidatedPickedImage, nowMillis: number): Promise<ImageTemporaryFile> {
    if (this.failWrite) {
      return Promise.reject(new Error('cache unavailable'));
    }
    const file: ImageTemporaryFile = {
      path: `${CACHE_DIR}/p4-images/0123456789abcdef0123456789abcdef.${image.descriptor.extension}`,
      mimeType: image.descriptor.mimeType,
      byteLength: image.byteLength,
      createdAtMillis: nowMillis
    };
    this.written.push(file);
    return Promise.resolve(file);
  }

  remove(file: ImageTemporaryFile): Promise<void> {
    this.removed.push(file.path);
    return Promise.resolve();
  }
}

function selection(uri: string = 'file://media/Photo/123'): PhotoPickerSelection {
  const image: PickedImage = { uri: uri, displayName: 'not-trusted.png', mimeType: 'text/plain' };
  const value: PhotoPickerSelection = { image: image };
  return value;
}

function selectedResult(uri: string = 'file://media/Photo/123'): PhotoPickerResult {
  const result: PhotoPickerResult = { kind: PhotoPickerResultKind.SELECTED, selections: [selection(uri)] };
  return result;
}

function cancelledResult(): PhotoPickerResult {
  const result: PhotoPickerResult = { kind: PhotoPickerResultKind.CANCELLED };
  return result;
}

function validInspection(uri: string = 'file://media/Photo/123'): PickedImageInspection {
  const inspection: PickedImageInspection = { sourceUri: uri, byteLength: 4096, headerBytes: PNG_HEADER };
  return inspection;
}

function coordinator(
  picker: SystemPhotoPickerGateway,
  inspector: FakePickedImageInspector,
  store: MemoryTemporaryStore
): MediaPickerCoordinator {
  return new MediaPickerCoordinator(picker, inspector, store, defaultMediaPickerRuntimePolicy(CACHE_DIR, NOW));
}

export default function mediaPickerCoordinatorTest(): void {
  describe('mediaPickerCoordinatorTest', () => {
    it('onlyPersistsExplicitlyPickedImagesAfterMagicAndLimitGates', 0, async () => {
      const picker = new FixedPhotoPickerGateway(selectedResult());
      const inspector = new FakePickedImageInspector();
      inspector.inspections.set('file://media/Photo/123', validInspection());
      const store = new MemoryTemporaryStore();
      const result = await coordinator(picker, inspector, store).pickExplicitly();

      expect(picker.calls).assertEqual(1);
      expect(picker.requestedMaxCount).assertEqual(9);
      expect(inspector.calls).assertEqual(1);
      expect(result.phase).assertEqual(MediaPickerPhase.READY);
      expect(result.images.length).assertEqual(1);
      expect(result.images[0].lifecycle.file.path.includes('/p4-images/')).assertTrue();
      expect(result.images[0].image.descriptor.mimeType).assertEqual('image/png');
      expect(store.written.length).assertEqual(1);
    });

    it('cancellationNeverInspectsOrPersistsAUserReference', 0, async () => {
      const picker = new FixedPhotoPickerGateway(cancelledResult());
      const inspector = new FakePickedImageInspector();
      const store = new MemoryTemporaryStore();
      const result = await coordinator(picker, inspector, store).pickExplicitly();

      expect(result.phase).assertEqual(MediaPickerPhase.CANCELLED);
      expect(result.images.length).assertEqual(0);
      expect(inspector.calls).assertEqual(0);
      expect(store.written.length).assertEqual(0);
    });

    it('rejectsInvalidMagicBeforeWritingTemporaryCache', 0, async () => {
      const picker = new FixedPhotoPickerGateway(selectedResult());
      const inspector = new FakePickedImageInspector();
      inspector.inspections.set('file://media/Photo/123', {
        sourceUri: 'file://media/Photo/123', byteLength: 4096, headerBytes: [0x00, 0x01]
      });
      const store = new MemoryTemporaryStore();
      const result = await coordinator(picker, inspector, store).pickExplicitly();

      expect(result.phase).assertEqual(MediaPickerPhase.FAILED);
      expect(result.failureKind).assertEqual(ImageUploadFailureKind.UNSUPPORTED_FORMAT);
      expect(result.images.length).assertEqual(0);
      expect(store.written.length).assertEqual(0);
    });

    it('dropsLatePickerResultAfterCancellation', 0, async () => {
      const picker = new DeferredPhotoPickerGateway();
      const inspector = new FakePickedImageInspector();
      inspector.inspections.set('file://media/Photo/123', validInspection());
      const store = new MemoryTemporaryStore();
      const value = coordinator(picker, inspector, store);
      const pending = value.pickExplicitly();
      const cancelled = await value.cancel();
      picker.resolve(selectedResult());
      const late = await pending;

      expect(cancelled.phase).assertEqual(MediaPickerPhase.CANCELLED);
      expect(late.phase).assertEqual(MediaPickerPhase.CANCELLED);
      expect(inspector.calls).assertEqual(0);
      expect(store.written.length).assertEqual(0);
    });

    it('releaseDeletesOnlyControlledFilesAfterAReadySelection', 0, async () => {
      const picker = new FixedPhotoPickerGateway(selectedResult());
      const inspector = new FakePickedImageInspector();
      inspector.inspections.set('file://media/Photo/123', validInspection());
      const store = new MemoryTemporaryStore();
      const value = coordinator(picker, inspector, store);
      const ready = await value.pickExplicitly();
      const released = await value.release();

      expect(ready.phase).assertEqual(MediaPickerPhase.READY);
      expect(released.phase).assertEqual(MediaPickerPhase.RELEASED);
      expect(released.images.length).assertEqual(0);
      expect(store.removed.length).assertEqual(1);
      expect(store.removed[0].includes('/p4-images/')).assertTrue();
    });

    it('clearSelectionPurgesPreparedCacheAndDoesNotRetainAnImageReference', 0, async () => {
      const picker = new FixedPhotoPickerGateway(selectedResult());
      const inspector = new FakePickedImageInspector();
      inspector.inspections.set('file://media/Photo/123', validInspection());
      const store = new MemoryTemporaryStore();
      const value = coordinator(picker, inspector, store);
      const ready = await value.pickExplicitly();
      const cleared = await value.cancel();

      expect(ready.phase).assertEqual(MediaPickerPhase.READY);
      expect(cleared.phase).assertEqual(MediaPickerPhase.CANCELLED);
      expect(cleared.images.length).assertEqual(0);
      expect(store.removed.length).assertEqual(1);
    });

    it('removesOnlyTheChosenControlledPreviewAndKeepsOtherPreparedImages', 0, async () => {
      const selected: PhotoPickerResult = {
        kind: PhotoPickerResultKind.SELECTED,
        selections: [selection('file://media/Photo/1'), selection('file://media/Photo/2')]
      };
      const picker = new FixedPhotoPickerGateway(selected);
      const inspector = new FakePickedImageInspector();
      inspector.inspections.set('file://media/Photo/1', validInspection('file://media/Photo/1'));
      inspector.inspections.set('file://media/Photo/2', validInspection('file://media/Photo/2'));
      const store = new MemoryTemporaryStore();
      const value = coordinator(picker, inspector, store);
      const ready = await value.pickExplicitly();
      const removed = await value.removePreparedImage(0);

      expect(ready.images.length).assertEqual(2);
      expect(removed.phase).assertEqual(MediaPickerPhase.READY);
      expect(removed.images.length).assertEqual(1);
      expect(removed.images[0].image.sourceUri).assertEqual('file://media/Photo/2');
      expect(store.removed.length).assertEqual(1);
      const ignored = await value.removePreparedImage(7);
      expect(ignored.phase).assertEqual(MediaPickerPhase.READY);
      expect(ignored.images.length).assertEqual(1);
      expect(store.removed.length).assertEqual(1);
    });

    it('restoresControlledDraftImagesAndAppendsNewExplicitSelectionsWithoutDeletingTheDraftCopy', 0, async () => {
      const firstPicker = new FixedPhotoPickerGateway(selectedResult('file://media/Photo/1'));
      const inspector = new FakePickedImageInspector();
      inspector.inspections.set('file://media/Photo/1', validInspection('file://media/Photo/1'));
      inspector.inspections.set('file://media/Photo/2', validInspection('file://media/Photo/2'));
      const store = new MemoryTemporaryStore();
      const initial = await coordinator(firstPicker, inspector, store).pickExplicitly();
      const nextPicker = new FixedPhotoPickerGateway(selectedResult('file://media/Photo/2'));
      const value = coordinator(nextPicker, inspector, store);

      const restored = value.restorePreparedImages(initial.images);
      const selected = await value.pickExplicitly();

      expect(restored.phase).assertEqual(MediaPickerPhase.READY);
      expect(restored.images.length).assertEqual(1);
      expect(nextPicker.requestedMaxCount).assertEqual(8);
      expect(selected.images.length).assertEqual(2);
      expect(store.removed.length).assertEqual(0);
    });
  });
}
