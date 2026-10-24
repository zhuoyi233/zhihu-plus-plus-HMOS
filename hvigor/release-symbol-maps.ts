import { copyFileSync, existsSync, mkdirSync, readFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';

/** 编译器仍可能生成热重载符号表；发行打包前转存到包外，供本地诊断使用。 */
export function archiveReleaseSymbolMap(etsDirectory: string, mappingDirectory: string): boolean {
  const source = join(etsDirectory, 'symbolMap.map');
  if (!existsSync(source)) {
    return false;
  }
  const target = join(mappingDirectory, 'symbolMap.map');
  mkdirSync(mappingDirectory, { recursive: true });
  copyFileSync(source, target);
  if (!readFileSync(source).equals(readFileSync(target))) {
    throw new Error(`符号映射归档校验失败：${target}`);
  }
  unlinkSync(source);
  console.info(`Release 符号映射已移至包外：${target}`);
  return true;
}
