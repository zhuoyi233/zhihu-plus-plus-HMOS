/** 只保存段落身份与块内比例，不保存正文、Cookie 或绝对像素偏移。 */
export interface ReaderPosition {
  version: number;
  blockId: string;
  signature: string;
  blockIndex: number;
  fraction: number;
  atEnd: boolean;
}

export const MAX_READER_POSITIONS: number = 100;

export function readerPositionKey(kind: string, id: string): string {
  return (kind === 'answer' || kind === 'article') && /^[1-9][0-9]{0,29}$/.test(id)
    ? `${kind}:${id}` : '';
}

function validKey(key: string): boolean {
  return /^(answer|article):[1-9][0-9]{0,29}$/.test(key);
}

export function decodeReaderPosition(raw: string): ReaderPosition | undefined {
  try {
    const value = JSON.parse(raw) as ReaderPosition;
    if (value === null || typeof value !== 'object' || value.version !== 1 ||
      typeof value.blockId !== 'string' || value.blockId.length > 128 ||
      typeof value.signature !== 'string' || !/^[0-9a-f]{8}$/.test(value.signature) ||
      !Number.isSafeInteger(value.blockIndex) || value.blockIndex < -1 || value.blockIndex > 100000 ||
      typeof value.fraction !== 'number' || !Number.isFinite(value.fraction) ||
      value.fraction < 0 || value.fraction > 1 || typeof value.atEnd !== 'boolean') {
      return undefined;
    }
    const position: ReaderPosition = {
      version: 1, blockId: value.blockId, signature: value.signature,
      blockIndex: value.blockIndex, fraction: value.fraction, atEnd: value.atEnd
    };
    return position;
  } catch (_error) {
    return undefined;
  }
}

export interface ReaderPositionStorage {
  read(key: string): string;
  write(key: string, value: string): void;
  remove(key: string): void;
  flush(synchronous: boolean): void;
}

/** 同步更新共享 Preferences 缓存；每条记录单独存储，避免超过字符串值的大小限制。 */
export class ReaderPositionRepository {
  private readonly storage: ReaderPositionStorage;

  constructor(storage: ReaderPositionStorage) {
    this.storage = storage;
  }

  load(key: string): ReaderPosition | undefined {
    return validKey(key) ? decodeReaderPosition(this.storage.read(key)) : undefined;
  }

  save(key: string, position: ReaderPosition, synchronous: boolean = false): void {
    if (!validKey(key) || decodeReaderPosition(JSON.stringify(position)) === undefined) {
      return;
    }
    let keys: string[] = [];
    try {
      const raw = JSON.parse(this.storage.read('recent')) as string[];
      if (Array.isArray(raw)) {
        keys = raw.filter((item: string): boolean => typeof item === 'string' && validKey(item));
      }
    } catch (_error) {
      // 损坏的索引不阻塞当前内容的保存。
    }
    const recent: string[] = [key];
    keys.forEach((item: string): void => {
      if (!recent.includes(item)) { recent.push(item); }
    });
    recent.slice(MAX_READER_POSITIONS).forEach((item: string): void => this.storage.remove(item));
    this.storage.write(key, JSON.stringify(position));
    this.storage.write('recent', JSON.stringify(recent.slice(0, MAX_READER_POSITIONS)));
    this.storage.flush(synchronous);
  }
}
