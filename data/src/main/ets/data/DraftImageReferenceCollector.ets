import { DraftImageReferenceScanSource } from './ContentDraftStore';
import { isParsableLocalDraftImageReferences, parseLocalDraftImageReferences } from './LocalDraftImageReferences';

export interface DraftImageReferenceScan {
  /** false 表示数据库读取失败或引用 JSON 损坏：清理调度必须停止破坏性回收并等待重试。 */
  readonly complete: boolean;
  /** 全部账号、回答与想法草稿引用的受控随机文件名。 */
  readonly fileNames: Set<string>;
}

/**
 * 缓存维护专用：把本机所有草稿引用收敛为受控文件名集合。
 * 只消费受控引用 JSON，不向调用方暴露草稿正文、账号键或草稿标题；
 * 任何一行不可解析都标记扫描不完整，宁可少回收也不误删被引用文件。
 */
export async function collectReferencedDraftImageFileNames(source: DraftImageReferenceScanSource):
  Promise<DraftImageReferenceScan> {
  let rows: Array<string>;
  try {
    rows = await source.listAllImageRefsJsonForMaintenance();
  } catch (_error) {
    return { complete: false, fileNames: new Set<string>() };
  }
  const fileNames: Set<string> = new Set<string>();
  for (let index = 0; index < rows.length; index += 1) {
    const serialized = rows[index];
    if (serialized.length === 0) {
      continue;
    }
    if (!isParsableLocalDraftImageReferences(serialized)) {
      return { complete: false, fileNames: new Set<string>() };
    }
    const references = parseLocalDraftImageReferences(serialized);
    for (let item = 0; item < references.length; item += 1) {
      fileNames.add(references[item].fileName);
    }
  }
  return { complete: true, fileNames: fileNames };
}
