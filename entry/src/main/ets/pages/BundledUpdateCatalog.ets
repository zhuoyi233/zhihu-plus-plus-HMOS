import { util } from '@kit.ArkTS';
import { AppUpdateClient } from 'data';
import { getAbilityContext } from '../entryability/AbilityContextHolder';

let loading: Promise<void> | undefined = undefined;

/** 发布时随 HAP 打包的清单，供静态远端尚未部署或网络暂不可用时展示当前版本。 */
export function seedBundledUpdateCatalog(): Promise<void> {
  if (loading !== undefined) {
    return loading;
  }
  loading = loadCatalog();
  return loading;
}

async function loadCatalog(): Promise<void> {
  const context = getAbilityContext();
  if (context === undefined) {
    return;
  }
  try {
    const latest = await context.resourceManager.getRawFileContent('update/version.json');
    const releases = await context.resourceManager.getRawFileContent('update/releases.json');
    const decoder = util.TextDecoder.create('utf-8');
    AppUpdateClient.seedBundledCatalog(decoder.decodeToString(latest), decoder.decodeToString(releases));
  } catch (_error) {
    // 本地清单损坏时仍可用远端与 Atom 备用源。
  }
}
