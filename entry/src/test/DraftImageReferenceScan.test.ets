import { describe, expect, it } from '@ohos/hypium';
import {
  collectReferencedDraftImageFileNames,
  DraftImageReferenceScanSource,
  isParsableLocalDraftImageReferences,
  LocalDraftImageReference,
  serializeLocalDraftImageReferences
} from 'data';

const FIRST_NAME: string = '0123456789abcdef0123456789abcdef.png';
const SECOND_NAME: string = 'fedcba9876543210fedcba9876543210.jpg';

function reference(fileName: string): LocalDraftImageReference {
  const item: LocalDraftImageReference = {
    fileName: fileName,
    mimeType: fileName.endsWith('.jpg') ? 'image/jpeg' : 'image/png',
    byteLength: 4096,
    width: 3,
    height: 2,
    animated: false,
    createdAtMillis: 1770000000000
  };
  return item;
}

class FakeDraftImageReferenceScanSource implements DraftImageReferenceScanSource {
  private readonly rows: Array<string>;
  private readonly failRead: boolean;

  constructor(rows: Array<string>, failRead: boolean = false) {
    this.rows = rows;
    this.failRead = failRead;
  }

  async listAllImageRefsJsonForMaintenance(): Promise<Array<string>> {
    if (this.failRead) {
      throw new Error('database unavailable');
    }
    return this.rows;
  }
}

export default function draftImageReferenceScanTest(): void {
  describe('draftImageReferenceScanTest', () => {
    it('distinguishesParsableReferenceJsonFromCorruptData', 0, () => {
      expect(isParsableLocalDraftImageReferences('[]')).assertTrue();
      expect(isParsableLocalDraftImageReferences(serializeLocalDraftImageReferences([reference(FIRST_NAME)])))
        .assertTrue();
      expect(isParsableLocalDraftImageReferences('')).assertFalse();
      expect(isParsableLocalDraftImageReferences('not-json')).assertFalse();
      expect(isParsableLocalDraftImageReferences('{"fileName":"x.png"}')).assertFalse();
      expect(isParsableLocalDraftImageReferences('[{"fileName":"../../outside.png"}]')).assertFalse();
      expect(isParsableLocalDraftImageReferences(
        '[' + serializeLocalDraftImageReferences([reference(FIRST_NAME)]).substring(1) + ',{"broken":true}]'))
        .assertFalse();
    });

    it('collectsControlledFileNamesAcrossAllAccountDraftRows', 0, async () => {
      const scan = await collectReferencedDraftImageFileNames(new FakeDraftImageReferenceScanSource([
        '', serializeLocalDraftImageReferences([reference(FIRST_NAME)]),
        serializeLocalDraftImageReferences([reference(SECOND_NAME), reference(FIRST_NAME)])
      ]));

      expect(scan.complete).assertTrue();
      expect(scan.fileNames.size).assertEqual(2);
      expect(scan.fileNames.has(FIRST_NAME)).assertTrue();
      expect(scan.fileNames.has(SECOND_NAME)).assertTrue();
    });

    it('marksScanIncompleteOnCorruptReferenceJsonInsteadOfDroppingProtection', 0, async () => {
      const scan = await collectReferencedDraftImageFileNames(new FakeDraftImageReferenceScanSource([
        serializeLocalDraftImageReferences([reference(FIRST_NAME)]), 'corrupt'
      ]));

      expect(scan.complete).assertFalse();
      expect(scan.fileNames.size).assertEqual(0);
    });

    it('marksScanIncompleteWhenDatabaseReadFails', 0, async () => {
      const scan = await collectReferencedDraftImageFileNames(new FakeDraftImageReferenceScanSource([], true));

      expect(scan.complete).assertFalse();
      expect(scan.fileNames.size).assertEqual(0);
    });
  });
}
