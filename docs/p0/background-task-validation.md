# P0 后台任务约束验证

> 验证日期：2026-08-10<br>
> 工具链：DevEco Studio 6.1.1 Release<br>
> 开发、目标与最低兼容版本：HarmonyOS 6.1.1（API 24）

## 结论

`P0-BG-01` 通过。首版不照搬 Android `WorkManager` 或常驻调度逻辑，而是按业务目的选择 HarmonyOS 后台机制：

| 业务负载 | 首版路由 | 边界 |
| --- | --- | --- |
| 用户主动刷新、推荐计算 | 前台执行 | 由可见页面和用户操作触发 |
| 已开始请求的有限收尾 | 短时任务 | 只完成在途操作，不借机启动新任务 |
| 非紧急、可延后的维护 | 延迟任务 | 由系统根据时间、网络和电量条件择机执行 |
| 音频播放 | 后置的长时任务 | 必须是用户可感知场景，提供通知和明确停止条件 |
| 周期 Feed 抓取、后台保活 | 不支持 | 首版禁止常驻或周期性抓取知乎 Feed |

TaskPool 只用于并发计算，不能当作后台存活机制。P0 没有申请 `ohos.permission.KEEP_BACKGROUND_RUNNING`，也没有执行真实知乎接口轮询或 Feed 抓取。

## 官方接口依据

- [HarmonyOS SDK 文档中心](https://developer.huawei.com/consumer/cn/doc/)中的 Background Tasks Kit 将任务区分为短时、长时、延迟任务和代理提醒。
- API 24 SDK 的 `@kit.BackgroundTasksKit` 导出 `backgroundTaskManager`、`workScheduler` 和 `WorkSchedulerExtensionAbility`。
- `backgroundTaskManager` 提供短时任务申请、剩余时间/配额查询和主动释放接口。
- `workScheduler` 提供延迟任务登记、状态查询、枚举和停止接口；回调由 `WorkSchedulerExtensionAbility` 承载。
- 长时任务要求匹配系统支持的用户可感知模式，并申请 `KEEP_BACKGROUND_RUNNING`；本项目当前没有合规的首版业务需求，因此不申请。

本次实现同时对照 DevEco Studio 安装目录内 API 24 声明：`openharmony/ets/kits/@kit.BackgroundTasksKit.d.ts`、`openharmony/ets/api/@ohos.resourceschedule.backgroundTaskManager.d.ts`、`@ohos.resourceschedule.workScheduler.d.ts` 和 `@ohos.WorkSchedulerExtensionAbility.d.ts`。

## 原型与自动检查

- `BackgroundWorkPolicy.ets` 固化五类负载的路由和通知要求。
- `BackgroundTaskProbe.ets` 申请短时任务后读取时间与当日配额，并在 `finally` 中主动释放。
- 同一探针登记一次性延迟任务 `24001`，查询登记状态后停止任务，再次枚举确认没有残留。
- `P0WorkSchedulerExtensionAbility` 只服务本次一次性原型；若系统在 UI 清理前触发，也会立即停止。
- Hypium 策略测试覆盖前台、短时、延迟、长时用户可感知和禁止 Feed 抓取五条路由。

## API 24 虚拟机结果

| 检查项 | 实测结果 | 状态 |
| --- | --- | --- |
| Debug HAP 安装与启动 | 成功 | 通过 |
| 短时任务申请 | 本次获批 180 秒 | 通过 |
| 剩余时间查询 | 读取时剩余 180 秒 | 通过 |
| 当日配额查询 | 读取时剩余 600 秒 | 通过 |
| 短时任务释放 | 主动取消成功 | 通过 |
| 延迟任务登记 | 任务 `24001`，最早 60 秒后触发 | 通过 |
| 延迟任务清理 | 停止后再次枚举为 0 | 通过 |
| UI 可视检查 | 状态完整可读，无裁切或崩溃 | 通过 |

180 秒和 600 秒是该次虚拟机返回值，只证明 API 与配额查询链路可用，不能作为产品永久配额或任务时长假设。

## 后续约束

- P1 的刷新、分页、签名和推荐评分默认跟随前台生命周期和取消信号。
- 只有明确可延后、幂等且失败可重试的维护工作才进入延迟任务。
- 不使用短时任务实现轮询，不通过延迟任务制造高频周期调度。
- 未来接入音频播放或用户可感知传输时，必须单独评审系统模式、通知、权限、停止条件、功耗和上架规范。
- 若业务目标发生变化，需要先更新本报告和策略测试，再修改平台实现。
