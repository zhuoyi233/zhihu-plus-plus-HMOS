import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { QrScanner } from './P4PlatformServices';

/** 仅在平台适配层调用 Scan Kit；页面只依赖 QrScanner。 */
export class QrScannerServiceFailure extends Error {
  readonly code: number | undefined;

  constructor(code: number | undefined) {
    super('QR scan service failed');
    this.code = code;
  }
}

export class SystemQrScanner implements QrScanner {
  private readonly context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  async scanSingleQrCode(): Promise<string | undefined> {
    try {
      const result = await scanBarcode.startScanForResult(this.context, {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableMultiMode: false,
        enableAlbum: true
      }).catch((error: BusinessError) => {
        throw new QrScannerServiceFailure(error.code);
      });
      const value = result.originalValue.trim();
      return value.length === 0 ? undefined : value;
    } catch (error) {
      if (error instanceof QrScannerServiceFailure) {
        throw new QrScannerServiceFailure(error.code);
      }
      throw new QrScannerServiceFailure(undefined);
    }
  }
}
