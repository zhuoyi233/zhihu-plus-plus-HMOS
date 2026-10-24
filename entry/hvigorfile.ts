import { HvigorNode } from '@ohos/hvigor';
import { hapTasks, OhosHapContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { join } from 'node:path';
import { archiveReleaseSymbolMap } from '../hvigor/release-symbol-maps';

export default {
  system: hapTasks,
  plugins: [{
    pluginId: 'zhplus-release-symbol-maps',
    apply(node: HvigorNode): void {
      node.afterNodeEvaluate(() => {
        const context = node.getContext(OhosPluginId.OHOS_HAP_PLUGIN) as OhosHapContext;
        if (context.getBuildMode() !== 'release') {
          return;
        }
        context.targets((target) => {
          const taskName = `${target.getTargetName()}@PackageHap`;
          const task = node.getTaskByName(taskName);
          if (!task) {
            throw new Error(`缺少发行打包任务：${taskName}`);
          }
          task.beforeRun(() => {
            const etsDirectory = join(target.getModulePathDetails().getModuleBuildPath(),
              target.getCurrentProduct().getProductName(), 'intermediates', 'loader_out',
              target.getTargetName(), 'ets');
            archiveReleaseSymbolMap(etsDirectory, join(target.getBuildTargetOutputPath(), 'mapping'));
          });
        });
      });
    }
  }]
};
