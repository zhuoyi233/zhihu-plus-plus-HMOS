import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ReaderPositionRepository, ReaderPositionStorage } from './ReaderPosition';

class PreferencesReaderPositionStorage implements ReaderPositionStorage {
  private readonly store: preferences.Preferences;

  constructor(context: common.Context) {
    this.store = preferences.getPreferencesSync(context, { name: 'reader_positions' });
  }

  read(key: string): string {
    const value = this.store.getSync(key, '');
    return typeof value === 'string' ? value : '';
  }

  write(key: string, value: string): void {
    this.store.putSync(key, value);
  }

  remove(key: string): void {
    this.store.deleteSync(key);
  }

  flush(synchronous: boolean): void {
    if (synchronous) {
      this.store.flushSync();
    } else {
      void this.store.flush().catch((_error: Object): void => {
        console.error('Reading position flush failed');
      });
    }
  }
}

export function createReaderPositionStore(context: common.Context): ReaderPositionRepository {
  return new ReaderPositionRepository(new PreferencesReaderPositionStorage(context));
}
