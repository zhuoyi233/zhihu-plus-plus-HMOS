import { fileIo } from '@kit.CoreFileKit';
import {
  LEGACY_SHARE_TEMPORARY_DIRECTORY,
  SHARE_TEMPORARY_DIRECTORY,
  SHARE_TEMPORARY_MAX_AGE_MILLIS
} from './ShareContracts';

const SHARE_FILE_NAME: RegExp = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;

/**
 * 分享临时目录的受控回收。当前生产代码没有本地文件分享载荷的生产者，此清理器只按保守年龄规则
 * 覆盖新旧专用目录里的孤立残留：仅枚举两个固定目录、仅删除符合应用命名规则的普通文件；
 * 未来时间戳、未知名称、嵌套目录和链接一律保留待检查。不递归删除目录。
 * 分享面板可能仍在读取的文件按 24 小时总寿命兜底；未接入创建记录前不做更激进的回收。
 */
export async function purgeExpiredShareTemporaryFiles(cacheDir: string, nowMillis: number = Date.now()): Promise<number> {
  const normalizedCacheDir = normalizeCacheDir(cacheDir);
  if (!Number.isSafeInteger(nowMillis) || nowMillis < 0) {
    throw new Error('Share cache purge timestamp is invalid');
  }
  const directories: Array<string> = [
    `${normalizedCacheDir}/${SHARE_TEMPORARY_DIRECTORY}`,
    `${normalizedCacheDir}/${LEGACY_SHARE_TEMPORARY_DIRECTORY}`
  ];
  let removedCount = 0;
  for (let directoryIndex = 0; directoryIndex < directories.length; directoryIndex += 1) {
    const directory = directories[directoryIndex];
    let entries: Array<string>;
    try {
      entries = await fileIo.listFile(directory);
    } catch (_error) {
      continue;
    }
    for (let index = 0; index < entries.length; index += 1) {
      const entry = entries[index];
      if (!SHARE_FILE_NAME.test(entry) || entry.includes('..')) {
        continue;
      }
      const path = `${directory}/${entry}`;
      try {
        const stat = await fileIo.stat(path);
        if (!stat.isFile() || !Number.isSafeInteger(stat.mtime) || stat.mtime < 0 ||
          stat.mtime * 1000 > nowMillis || nowMillis < stat.mtime * 1000 + SHARE_TEMPORARY_MAX_AGE_MILLIS) {
          continue;
        }
        await fileIo.unlink(path);
        removedCount += 1;
      } catch (_error) {
        // 文件在枚举后被正常清理或不可访问时不重试，也不泄漏其名称。
      }
    }
  }
  // 旧目录不再有新写入；已清空时尝试移除目录本身，失败留待下次重试。
  try {
    await fileIo.rmdir(`${normalizedCacheDir}/${LEGACY_SHARE_TEMPORARY_DIRECTORY}`);
  } catch (_error) {
  }
  return removedCount;
}

function normalizeCacheDir(value: string): string {
  const normalized = value.replace(/\\/g, '/').replace(/\/+$/g, '');
  if (!/^\/[A-Za-z0-9._/-]+$/.test(normalized) || normalized.includes('..')) {
    throw new Error('Share cache directory is invalid');
  }
  return normalized;
}
