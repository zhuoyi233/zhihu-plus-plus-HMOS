import { collectReferencedDraftImageFileNames, DraftImageReferenceScanSource } from 'data';
import { purgeExpiredControlledImageCache } from './SystemPickedImageFileStore';

/**
 * 启动缓存维护入口：先完成全账号草稿引用扫描，再回收无引用且超过 24 小时的受控图片缓存。
 * 维护只在启动时执行一次，此时编辑器尚未挂载，不存在正在编辑中的“活动使用者”；
 * 引用扫描失败或发现损坏 JSON 时跳过本次图片清理——宁可少回收，也不误删被引用文件。
 */
export async function maintainControlledImageCaches(cacheDir: string,
  referenceSource: DraftImageReferenceScanSource, nowMillis: number = Date.now()): Promise<void> {
  const scan = await collectReferencedDraftImageFileNames(referenceSource);
  if (!scan.complete) {
    return;
  }
  try {
    await purgeExpiredControlledImageCache(cacheDir, nowMillis, scan.fileNames);
  } catch (_error) {
    // 清理失败不影响启动；下个启动周期按实际文件状态重试。
  }
}
