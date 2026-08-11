# P1 UI 与导航基座验证

## 范围

本批次建立 P1 的根 UI 基座，目标版本为 HarmonyOS 6.1.1（API 24），不包含端侧 AI：

- 根页面使用 `Navigation` 与单一 `NavPathStack`。
- 根页面内容放在满尺寸 `Alignment.TopStart` 容器内，滚动内容从标题栏下方开始；根导航栏隐藏返回键，子目的地仍使用正常返回栈。
- 目的地使用 `P1Destination` 联合类型，内容 ID 始终保持字符串；系统栈回调会再次解码和校验名称、参数类型及非空 ID。
- P0 全部原型保留在“技术实验室”目的地，不再用根页面的一组布尔值代替导航栈。
- `base`/`dark` 使用同名颜色 token，跟随系统时由资源限定目录自动切换。
- 显示页支持跟随系统、强制浅色、强制深色，调用 API 24 可用的 `UIAbilityContext.setColorMode()`，并通过 `AppPreferencesStore` 恢复和保存选择。
- 所有新增字号使用 `fp` 资源，不设置 `maxFontScale`、固定文本高度或单行截断。
- `Navigation` 负责内容安全区，页面背景通过 `expandSafeArea` 延伸到系统顶部和底部区域。

实现依据：HarmonyOS 官方 [Navigation 指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-navigation-navigation) 与 [沉浸式效果和安全区说明](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-develop-apply-immersive-effects)。

## 强类型导航契约

`P1DestinationName` 预留迁移计划要求的目标：`Home`、`Question`、`Answer`、`Article`、`Video`、`Pin`、`People`、`Comment`、`Search`、`Collection`、`Notification`、`Settings`，并增加只供开发回归使用的 `TechnicalLab`、六个 P0 probe 和领域模型夹具门禁目的地。

参数按目的地分组：

| 类型 | 参数 |
| --- | --- |
| 无状态页面 | 仅强类型 `name` |
| 内容页面 | 字符串 `id` |
| 评论页面 | 字符串 `contentId`，可选字符串 `commentId` |
| 搜索页面 | 字符串 `query` |

UI 到 `NavPathStack` 的边界只接受完整的 `P1Destination`。`decodeP1Destination()` 在运行时拒绝未知名称、名称与参数不匹配、空内容 ID、空可选评论 ID，以及目的地不接受的多余参数。设置、技术实验室及其六个 probe 使用 `LaunchMode.MOVE_TO_TOP_SINGLETON`，重复点击不会留下相同页面的重复实例。

P0 原型不再由根页面的六个布尔值切换。`Index` 的 Builder 只实例化独立的 `TechnicalLabPage` 并传入强类型导航回调；网络、Cookie、登录、会话、client 与生命周期均由该组件自己持有。所有进入、返回和系统返回均由同一个 `NavPathStack` 管理。

API 24 设备曾在进入技术实验室时触发 `cookieInput.trim()` 的 `undefined` 崩溃。根因是跨组件传递 `Index` 实例 Builder 后，Builder 内部的 `this` 在 `P1Shell` 上下文执行，导致 `Index.@State` 不再属于实际接收者。将技术实验室迁为有职责的独立组件后，Builder 不再读取跨组件 `this` 状态，同时保留原 testTag、探针入口及回调。

## 启动目的地

`EntryAbility` 将 `resolveZhihuLink()` 的结果完整映射为 `P1Destination`，问题、回答、文章、视频、想法、用户、搜索和首页均有明确目标。`StartupDestinationChannel` 在页面订阅前只保留最新冷启动目标，页面订阅后立即交付；订阅期间使用稳定的目的地 identity 忽略连续重复 URI，避免同一页面重复入栈。`P1Shell` 对 API 24 首次订阅时可能尚未初始化的 `getPathStack()` 结果做运行时守卫，未初始化状态仍会 push 冷启动目的地；`onNewWant()` 向已订阅页面直接投递，因此冷、热两种启动路径都会进入实际导航栈，而不再只记录诊断日志。

生产数据库首次 `open()` 作为 `database-migration` 关键启动任务运行，`deep-link-routing` 明确依赖它；迁移失败会沿用关键阶段失败合同阻止 `loadContent`。Ability 销毁时触发 `closeAppDatabase()`，关闭失败不记录异常原文。

## 主题持久化

- `P1Shell.aboutToAppear()` 从 data 根包的 `AppPreferencesStore` 恢复 `AppThemeMode`，读取失败安全回落到跟随系统。
- 恢复和用户选择共享 generation 合同：较新的选择使旧恢复结果失效，组件离页使尚未完成的 UI 回调失效；重新进入时等待已有保存队列后再读取。
- 用户切换后先立即调用 `setColorMode()` 更新界面，再按顺序写入 Preferences。保存失败不回显异常原文，并明确显示“本次未保存”，避免把仅本次生效误报为已持久化。
- 主题枚举和持久化键只由 data 层定义，UI 不维护第二套字符串协议。

## 静态检查

- `P1Navigation.test.ets` 覆盖全部目的地名称、未知名称拒绝、19 位内容 ID 字符串语义、名称/参数匹配、空/多余参数拒绝、深链到启动目的地映射，以及未初始化导航栈仍允许冷启动目的地入栈的纯契约。
- `AppStartup.test.ets` 覆盖冷启动只消费最新目标、订阅期间重复目标去重，以及主题恢复/选择/离页的 generation 优先级。
- 按任务边界没有修改 `List.test.ets`；集成阶段应由主任务统一注册新测试。
- 已检查新增 UI 没有固定文本高度、`maxLines(1)` 或关闭字体缩放的属性。
- 已检查新增导航只保留一个承担“强类型到系统栈”契约的 `navigate()`，没有纯转发 helper。
- 技术实验室的三组双按钮已改为纵向全宽布局，间距和页面 padding 均使用资源 token，避免最大字体档下横向挤压。
- 首页、设置页和技术实验室均使用满尺寸 `Alignment.TopStart` 容器包裹滚动区；设置页固定 testTag `p1_settings_top_start_container`、`p1_settings_scroll`，技术实验室固定 `p1_technical_lab_top_start_container`、`p1_technical_lab_scroll`，可据此比较标题栏与正文边界。无效参数页和业务占位页也显式顶对齐。
- 安全区仅完成代码接入；是否存在遮挡、不可触达区域仍保留为 API 24 设备验证项，不以静态检查宣称通过。

## 定向验证

- `devecocli build --product default --modules entry --build-mode debug`：`BUILD SUCCESSFUL`。
- `scripts/verify-harmony.ps1 -ExpectedTestCount 89`：API 24 四模块构建成功；新生成的 entry Hypium 原始 `test_result.txt` 为 `Tests run: 89, Failure: 0, Error: 0, Pass: 89, Ignore: 0`。

## API 24 设备结果

验证设备为 DevEco 虚拟机 `ZhihuPlus_API24`，HarmonyOS 6.1.1（API 24），分辨率 1320 × 2856，系统处于大字体显示状态：

- 首页正文从 TitleBar 下边界 y=332 开始，`p1_home_title` 位于 y=402；根页面无返回键，状态栏和底部手势区未遮挡内容。
- 设置页 `p1_settings_top_start_container` 从 y=332 开始，首项位于 y=465；技术实验室同样从标题栏下方顶对齐，纵向按钮在大字体下完整可滚动。
- 深色主题保存后强制停止并重启进程仍为深色；浅色与跟随系统均能即时切换，`p1_theme_persistence_status` 显示“主题设置已保存”。
- 冷启动 `zhihu://answers/12345` 进入 `Answer` 并保留字符串 ID；前台重复投递同一 URI 后返回一次即到首页，证明未重复入栈；热投递 `https://www.zhihu.com/question/67890` 正确进入 `Question`。
- 设备回归曾分别发现跨组件 Builder 的 `this` 绑定崩溃与冷启动未初始化 `NavPathStack` 崩溃；修复后的同一路径均已复测通过。

## 设备验证清单

本批次已在 DevEco API 24 虚拟机完成以下验证：

1. 首页可进入“显示与阅读”和“技术实验室”，系统返回键回到原页面。
2. 连续点击同一入口不会产生重复目的地。
3. 技术实验室中的网络、登录、正文、图片、数据库、深链、扫码和后台任务入口仍可用。
4. 分别切换跟随系统、浅色、深色，文字、页面、卡片和控件颜色均有足够对比度。
5. 系统字体设为默认与最大档，标题和正文均可完整换行，无重叠、裁切和横向溢出。
6. 状态栏、刘海/挖孔区和底部系统区域只延伸背景，交互内容不进入不可触达区域。

## 后续集成

- 主题模式已接入 P1 Preferences 仓库；后续新增显示偏好继续复用同一个 store，不在 UI 内另建同义存储。
- P2 注册业务页面时复用现有目的地参数类型；需要新增参数时先扩展对应联合类型，再注册 `NavDestination`。
- 页面返回栈、列表位置和瞬时弹层状态恢复需要在实际业务页面接入后做设备级闭环。
