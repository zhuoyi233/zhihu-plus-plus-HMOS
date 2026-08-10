# P1 UI 与导航基座验证

## 范围

本批次建立 P1 的根 UI 基座，目标版本为 HarmonyOS 6.1.1（API 24），不包含端侧 AI：

- 根页面使用 `Navigation` 与单一 `NavPathStack`。
- 目的地使用 `P1Destination` 联合类型，内容 ID 始终保持字符串。
- P0 全部原型保留在“技术实验室”目的地，不再用根页面的一组布尔值代替导航栈。
- `base`/`dark` 使用同名颜色 token，跟随系统时由资源限定目录自动切换。
- 显示页支持跟随系统、强制浅色、强制深色，调用 API 24 可用的 `UIAbilityContext.setColorMode()`。
- 所有新增字号使用 `fp` 资源，不设置 `maxFontScale`、固定文本高度或单行截断。
- `Navigation` 负责内容安全区，页面背景通过 `expandSafeArea` 延伸到系统顶部和底部区域。

实现依据：HarmonyOS 官方 [Navigation 指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-navigation-navigation) 与 [沉浸式效果和安全区说明](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-develop-apply-immersive-effects)。

## 强类型导航契约

`P1DestinationName` 预留迁移计划要求的目标：`Home`、`Question`、`Answer`、`Article`、`Pin`、`People`、`Comment`、`Search`、`Collection`、`Notification`、`Settings`，并增加只供开发回归使用的 `TechnicalLab`。

参数按目的地分组：

| 类型 | 参数 |
| --- | --- |
| 无状态页面 | 仅强类型 `name` |
| 内容页面 | 字符串 `id` |
| 评论页面 | 字符串 `contentId`，可选字符串 `commentId` |
| 搜索页面 | 字符串 `query` |

UI 到 `NavPathStack` 的边界只接受 `P1Destination`。基础设施页面使用 `LaunchMode.MOVE_TO_TOP_SINGLETON`，重复点击不会留下相同页面的重复实例。

## 静态检查

- `P1Navigation.test.ets` 覆盖全部目的地名称、未知名称拒绝、19 位内容 ID 字符串语义和两个已注册基础设施目的地。
- 按任务边界没有修改 `List.test.ets`；集成阶段应由主任务统一注册新测试。
- 已检查新增 UI 没有固定文本高度、`maxLines(1)` 或关闭字体缩放的属性。
- 已检查新增导航只保留一个承担“强类型到系统栈”契约的 `navigate()`，没有纯转发 helper。

## 设备验证清单

本批次按并行任务约定只完成代码与静态自审，尚未运行构建或模拟器。合并其他 P1 基础设施后应在 DevEco API 24 虚拟机验证：

1. 首页可进入“显示与阅读”和“技术实验室”，系统返回键回到原页面。
2. 连续点击同一入口不会产生重复目的地。
3. 技术实验室中的网络、登录、正文、图片、数据库、深链、扫码和后台任务入口仍可用。
4. 分别切换跟随系统、浅色、深色，文字、页面、卡片和控件颜色均有足够对比度。
5. 系统字体设为默认与最大档，标题和正文均可完整换行，无重叠、裁切和横向溢出。
6. 状态栏、刘海/挖孔区和底部系统区域只延伸背景，交互内容不进入不可触达区域。

## 后续集成

- 主题模式当前由 UIAbility 立即应用；持久化应接入 P1 Preferences 仓库，不能在 UI 内另建同义存储。
- P2 注册业务页面时复用现有目的地参数类型；需要新增参数时先扩展对应联合类型，再注册 `NavDestination`。
- 页面返回栈、列表位置和瞬时弹层状态恢复需要在实际业务页面接入后做设备级闭环。
