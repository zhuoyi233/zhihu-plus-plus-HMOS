import { describe, expect, it } from '@ohos/hypium';
import {
  HarmonySystemPhotoPickerGateway,
  SystemPhotoPickerClient,
  toPhotoPickerResult
} from '../main/ets/platform/SystemPhotoPickerGateway';
import { PhotoPickerResultKind } from '../main/ets/platform/MediaPickerCoordinator';

class RecordingPhotoPickerClient implements SystemPhotoPickerClient {
  result: Array<string> = [];
  error: Error | undefined = undefined;
  calls: number = 0;
  requestedMaxCount: number = 0;

  async selectImages(maxCount: number): Promise<Array<string>> {
    this.calls += 1;
    this.requestedMaxCount = maxCount;
    if (this.error !== undefined) {
      throw this.error;
    }
    return this.result;
  }
}

export default function systemPhotoPickerGatewayTest(): void {
  describe('systemPhotoPickerGatewayTest', () => {
    it('requestsOnlyImageSelectionsWithTheCoordinatorBound', 0, async () => {
      const client = new RecordingPhotoPickerClient();
      client.result = ['file://media/Photo/1'];
      const gateway = new HarmonySystemPhotoPickerGateway(client);
      const result = await gateway.pickImages(9);

      expect(client.calls).assertEqual(1);
      expect(client.requestedMaxCount).assertEqual(9);
      expect(result.kind).assertEqual(PhotoPickerResultKind.SELECTED);
      if (result.kind === PhotoPickerResultKind.SELECTED) {
        expect(result.selections.length).assertEqual(1);
        expect(result.selections[0].image.uri).assertEqual('file://media/Photo/1');
        expect(result.selections[0].image.displayName).assertEqual(undefined);
        expect(result.selections[0].image.mimeType).assertEqual(undefined);
      }
    });

    it('limitsAndDeduplicatesSystemUrisBeforeTheControlledInspector', 0, () => {
      const result = toPhotoPickerResult([
        '', 'file://media/Photo/1', 'file://media/Photo/1', '   ',
        'file://media/Photo/2', 'file://media/Photo/3'
      ], 2);

      expect(result.kind).assertEqual(PhotoPickerResultKind.SELECTED);
      if (result.kind === PhotoPickerResultKind.SELECTED) {
        expect(result.selections.length).assertEqual(2);
        expect(result.selections[0].image.uri).assertEqual('file://media/Photo/1');
        expect(result.selections[1].image.uri).assertEqual('file://media/Photo/2');
      }
    });

    it('treatsEmptySelectionAndSystemFailureAsCancellationWithoutRawError', 0, async () => {
      const client = new RecordingPhotoPickerClient();
      client.error = new Error('private picker diagnostic: user account');
      const gateway = new HarmonySystemPhotoPickerGateway(client);
      const failed = await gateway.pickImages(9);
      const empty = toPhotoPickerResult([], 9);

      expect(failed.kind).assertEqual(PhotoPickerResultKind.CANCELLED);
      expect(empty.kind).assertEqual(PhotoPickerResultKind.CANCELLED);
      expect(JSON.stringify(failed).includes('private picker diagnostic')).assertFalse();
    });

    it('doesNotCallThePlatformForOutOfRangeCounts', 0, async () => {
      const client = new RecordingPhotoPickerClient();
      const gateway = new HarmonySystemPhotoPickerGateway(client);
      const zero = await gateway.pickImages(0);
      const tooMany = await gateway.pickImages(501);

      expect(zero.kind).assertEqual(PhotoPickerResultKind.CANCELLED);
      expect(tooMany.kind).assertEqual(PhotoPickerResultKind.CANCELLED);
      expect(client.calls).assertEqual(0);
    });
  });
}
