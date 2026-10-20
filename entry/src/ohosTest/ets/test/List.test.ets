import remoteReadStoreDeviceTest from './RemoteReadStoreDevice.test';
import remoteHistorySyncTest from '../../../test/RemoteHistorySync.test';

export default function testsuite(): void {
  remoteHistorySyncTest();
  remoteReadStoreDeviceTest();
}
