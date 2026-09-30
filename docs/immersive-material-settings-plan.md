# 沉浸光感四挡设置实施计划

日期：2026-09-30  
分支：`codex/immersive-material-levels`  
状态：已实施（2026-09-30）；验证结果见第 8 节。  
依据：[沉浸光感挡位选择研究](immersive-material-level-selection.md)。

## 1. 目标与范围

在“设置 → 外观与阅读体验 → 主题”中增加“沉浸光感”四挡选择器：**自适应、精美、轻柔、流畅**。默认自适应；选中后即时更新应用现有 HDS 材质，并在重启后恢复。

本次实现范围为四挡单选，不增加第五个“关闭”选项。前期研究中的关闭方案不纳入本计划。保留最低 API 23 兼容线、现有材质能力检查、API 23 标题栏降级和温控策略。

验收重点：四挡可选、保存可靠、已挂载页面能够更新、设备不支持时正确降级，且不重建正文或丢失阅读位置。

## 2. 设置界面与交互

### 2.1 位置与样式

- 插在“主题颜色”之后、“悬浮按钮透明度”之前。
- 标题：**沉浸光感**。
- 采用四项单选 `SegmentButton`，顺序为“自适应 / 精美 / 轻柔 / 流畅”。点击立即应用，无需另设确认按钮。
- 控件下方显示当前选项的简短说明；外观与设置页现有卡片、字体、间距一致。
- 设置搜索增加“沉浸、光感、材质、自适应、精美、轻柔、流畅”等关键词，命中后显示现有“外观与阅读体验”入口。

| 显示名称 | 存储值 | HDS 等级 | 说明文案 |
| --- | --- | --- | --- |
| 自适应 | `adaptive` | `ADAPTIVE` | 根据设备性能自动选择材质效果 |
| 精美 | `exquisite` | `EXQUISITE` | 更精美的材质效果，性能开销较高 |
| 轻柔 | `gentle` | `GENTLE` | 使用轻柔的材质效果 |
| 流畅 | `smooth` | `SMOOTH` | 优先保证流畅，减少材质性能开销 |

“自适应”只显示系统决定等级，不显示未经查询确认的具体生效挡位。

### 2.2 控件实现要求

- `SegmentButton` 的 options 存在 `@State` 字段，设置明确宽度，避免内联对象导致真机点击回调丢失。
- 选中背景读取 `@StorageProp('resolvedThemeColor')`；选中文字使用 `onThemeColor(resolvedThemeColor)`。主题变化时同步更新 options 中的颜色。
- 单独编写 `immersiveMaterialSetting()` builder，在 builder 中直接读取状态。现有通用 `selectSetting()` 存在按值参数固化记录，不沿用该传参方式。
- 覆盖窄屏、深浅色、系统大字体和无障碍选中状态。四项若在大字体下无法完整显示，使用同一四项单选列表呈现，保持名称、顺序与语义一致。
- 为设置项和可操作选项提供稳定的 UI 定位方式；拟用设置项 ID `appearance_immersive_material_level`，具体子项 ID 按组件支持情况落地。

### 2.3 不支持设备与异常反馈

四挡始终可见，保存的是用户选择。对不支持 `IMMERSIVE` 的设备，精美和轻柔按流畅策略处理，并显示“当前设备暂不支持所选效果，已使用兼容效果”。已有普通模糊兜底区域继续使用原有渲染方式。

能力查询异常时显示“暂时无法确认设备支持情况，已使用兼容效果”。查询失败只影响本次生效策略，不覆盖用户保存的选择。

保存失败时保留本次已生效的选择，显示“沉浸光感设置保存失败，本次调整仍已生效”。同一选项在保存失败后允许重试；只有最新一次保存结果可以更新提示。

## 3. 偏好存储与启动恢复

### 3.1 数据定义

新增 `data/src/main/ets/preferences/ImmersiveMaterialPreferences.ets`：

- 定义字符串枚举 `ImmersiveMaterialMode`，仅包含上表四项。
- 定义默认值和解码函数；缺失、旧版本未存储、错误类型、未知字符串统一回退 `adaptive`。
- `data/Index.ets` 导出枚举与解码函数。
- 数据层仅保存产品选项，不引入 `@kit.UIDesignKit`；UI 层负责映射 HDS 枚举。

在 `AppPreferencesStore` 中增加独立偏好键 `immersiveMaterialLevel` 及对应 load/save 方法。采用独立键，避免修改现有 `AppearancePreferences` 整包保存接口后，被其他外观设置意外写回默认值。

### 3.2 状态流向

```text
启动读取偏好 → AppStorage.immersiveMaterialLevel
                     ↓
设置页及材质组件通过 @StorageProp 订阅
                     ↑
用户选四挡 → 更新 AppStorage → 即时更新材质
                     ↓
AppShell 统一监听并经持久化队列保存
```

- AppShell 为这项功能持有稳定的 `AppPreferencesStore` 实例，作为唯一写入入口，复用已有串行 `saveQueue`，保证快速切换最终保存最后一次选择。
- 启动先提供 `adaptive` 默认值，异步读取持久化值后发布。初始化期间不触发保存；设置控件在恢复完成前暂不可操作，避免旧读取结果覆盖用户刚选择的新值。
- 读取成功或失败都结束加载状态。读取失败保留默认值并提供简短提示，用户仍可重新选择和保存。
- 使用独立就绪状态，如 `immersiveMaterialPreferencesReady`；初始化广播与用户变更明确区分，避免恢复时重复写入。
- 设置页退出后，保存由 AppShell 继续完成，不依赖设置页生命周期。

## 4. 统一材质策略

新增 `entry/src/main/ets/common/style/ImmersiveMaterialStyles.ets`，集中处理选项到 `SystemMaterialParams` 的映射。能力查询继续复用 `HarmonyOSCapabilities`，补充能够区分“不支持”和“查询失败”的结果供提示使用。

| 用户选择 | 支持 `IMMERSIVE` | 不支持 / 查询失败 |
| --- | --- | --- |
| 自适应 | `ADAPTIVE` | HDS 仍交由系统自适应；现有能力门禁区域继续兜底 |
| 精美 | `EXQUISITE` | HDS 使用 `SMOOTH`；现有能力门禁区域继续兜底 |
| 轻柔 | `GENTLE` | HDS 使用 `SMOOTH`；现有能力门禁区域继续兜底 |
| 流畅 | `SMOOTH` | HDS 使用 `SMOOTH`；现有能力门禁区域继续兜底 |

材质类型统一保持 `MaterialType.ADAPTIVE`。参数解析应为可独立验证的纯映射，设备能力由调用方提供；不要在每次 build 中反复查询设备。

以下边界必须保持：

- API 23 标题栏仍经过 `supportsImmersiveTitleBarStyle()` 门禁，不因选择精美而绕开已有白色遮挡问题的处理。
- 保留 HdsTabs 现有 `thermoCtrl: true`。标题栏新增温控不属于这次四挡设置的必要改动。
- 不引入 API 26 专属 `uiMaterial`，不把四挡映射为玻璃厚薄参数。
- 手动选择不承诺所有设备或组件具有相同视效，也不承诺固定省电比例。

## 5. 全部材质接入点与即时刷新

### 5.1 HDS 底栏

修改 `ZhihuHdsTabs.ets` 中 `ZhihuHdsTabs`、`ZhihuHdsActionBar`：各组件通过 `@StorageProp('immersiveMaterialLevel')` 直接订阅，使用统一解析方法设置等级。

不要依赖 AppShell 的 builder 值传参或 `@Provide/@Consume` 将变更穿过 HdsTabs 构建树。

### 5.2 复用材质画布

当前 `materialCanvas(width, height)` 为全局 builder，等级硬编码。计划保留外部 builder 调用方式，在内部承载一个可自行订阅 AppStorage 的 `MaterialCanvas` 组件。

- 新组件接收宽高并自行读取挡位，原有 barWidth 三档断点、barHeight、透明背景、hitTest、温控和裁剪行为保持一致。
- 审计所有调用方：`GlassCapsule`、`AnswerTitleBar`、`ArticleTitleBar`、`CommentTitleBar`、`CommentLayer`、AppShell 内问题返回胶囊。
- 特别验证评论输入宽度变化和胶囊实测宽度更新，避免组件封装后出现尺寸不响应。
- builder 包装体仅调用组件；`@BuilderParam` 箭头体仅直接调用 builder，条件判断放入 builder 内部。

### 5.3 标题栏样式

- `NavStyles.ets` 中两个样式函数接收明确的挡位参数，统一应用材质策略。
- AppShell 订阅挡位，所有 `getImmersiveTitleBarStyle()`、`getPersistentImmersiveTitleBarStyle()` 调用点显式传入响应式值，避免样式函数内部只调用 `AppStorage.get()` 而无法建立更新依赖。
- 对已挂载、暂时隐藏及导航返回后恢复的目的页逐项验证。如 HDS 对已创建 titleBar 不响应更新，先在最小场景确认，再调整标题栏局部状态更新方式；不得靠重建整页或路由栈实现刷新。
- 切换不触发 feed reload，不改变登录状态、当前页签、正文滚动位置、评论输入或阅读进度。

## 6. 实施顺序

| 阶段 | 工作 | 完成标准 |
| --- | --- | --- |
| 1. 数据与策略 | 四项枚举、独立存储键、统一映射、能力状态 | 缺省与非法值处理明确；高挡降级可验证 |
| 2. 状态与存储 | 启动恢复、AppStorage 广播、唯一保存入口及失败反馈 | 连续切换、退出设置、重启均保留最终选择 |
| 3. 材质接入 | 底栏、画布、标题栏全部使用统一策略 | 已挂载区域响应变更，阅读状态保留 |
| 4. 设置 UI | 四项选择器、说明、主题联动和搜索词 | 四项可操作，窄屏与大字体可读 |
| 5. 验证 | 自动化、按顺序构建、设备回归、截图 | 下述验收项完成，未验证项明确记录 |

各阶段在当前分支完成。提交与推送遵循仓库要求，仅在用户当次明确要求时执行。

## 7. 验证与验收

### 7.1 自动化

新增有行为价值的 Hypium 用例，并按需在 `entry/src/test/List.test.ets` 注册：

- 老版本无偏好、未知字符串与错误类型均回退自适应。
- 支持、未支持、能力查询失败下的四挡映射符合策略表。
- 快速切换及中途保存失败后，队列仍能保存最终值；过期结果不覆盖最新提示。
- 启动恢复不会写回默认值；修改其他外观设置不覆盖此偏好。

持久化和页面传播的测试根据现有测试环境选择集成测试或设备回归，不用只比较常量的测试代替验证。纯 Hypium 测试不能证明真实 GPU 材质已刷新。

### 7.2 构建顺序

完成代码后，使用 PowerShell 7 依次执行：

```powershell
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -SkipBuild
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall
```

用例总数由脚本动态统计。此功能验证使用 Debug 包，不涉及版本号或 Release 出包。

### 7.3 设备回归

默认目标为 `ZhihuPlus_API23`（`127.0.0.1:5555`）。先完成该模拟器的兼容、交互、保存和导航验证；视觉及发热评估还需实际支持沉浸材质的 API 23/API 26 真机。未具备的设备条件在结果中注明。

- 首次安装和旧数据升级均默认自适应；四挡互切、重复选择及重启恢复正常。
- 从已有详情页进入设置后切挡，返回首页、详情、评论时，底栏和胶囊采用最新策略。
- API 26 标题栏随挡位更新；API 23 标题栏保持现有兼容效果，无不透明白条回归。
- 深浅色与主题色变化后，四挡选中态、文字、图标可读；窄屏和大字体无裁切。
- 无材质支持及能力失败路径反馈准确，不强制启用高挡。
- 保存失败可重试；快速切换后立即离开设置，再重启仍恢复最后成功保存的选择。
- 详情阅读位置、当前页签、评论输入和底栏自动隐藏行为保持正常。
- 真机在相同内容与背景下比较四挡；长列表滚动关注帧率与发热。没有测量数据时不写功耗改善结论。

截图使用 `docs/ui-screenshots/immersive-material-*.jpg` 命名，标注设备、系统、模式和选项，作为实施后的验证材料。

## 8. 当前交付状态

### 8.1 已实施（2026-09-30，分支 `codex/immersive-material-levels`）

- 数据层：`data/.../preferences/ImmersiveMaterialPreferences.ets`（四挡枚举、默认值、双解码函数，未知/缺失/错型回退自适应）；
  `AppPreferencesStore` 独立键 `immersiveMaterialLevel` 走既有串行 `saveQueue`；`data/Index.ets` 导出。
- 策略层：`entry/.../common/style/ImmersiveMaterialStyles.ets`（能力三态 + 纯映射 `resolveImmersiveMaterialLevel` +
  降级/查询失败提示文案，不依赖 `@kit.UIDesignKit`，可被本地单测装载）；`HdsMaterialLevels.ets` 为 UI 侧 HDS 枚举薄转换；
  `HarmonyOSCapabilities` 新增三态查询 `immersiveMaterialSupportState()`。
- 状态流：AppShell 启动广播默认值 → 异步恢复持久化值 → `immersiveMaterialPreferencesReady` 就绪后设置控件才可操作；
  AppShell 持有唯一 store 实例作唯一写入入口，保存失败经 `immersiveMaterialNotice` 提示且保留已生效选择。
- 材质接入：`ZhihuHdsTabs`/`ZhihuHdsActionBar`、`MaterialCanvas`（builder 内组件自订阅，宽高 @Prop 保留实测宽度更新）、
  `NavStyles` 两样式函数显式接收挡位参数，AppShell 46 处调用点传入响应式值；API 23 标题栏门禁、`thermoCtrl`、
  组件模糊兜底均未改动。
- 设置 UI：主题卡片内“主题颜色”之后插入四挡 `SegmentButton`（`@State` options + 主题色 `@Watch` 重建），
  说明区按“保存提示 > 能力降级提示 > 选项说明”优先级展示；设置搜索新增“沉浸/光感/材质/自适应/精美/轻柔/流畅”关键词。
- 自动化：新增 `ImmersiveMaterialPreferences.test.ets`、`ImmersiveMaterialStyles.test.ets` 并注册，
  Hypium 710/710 通过（`verify-harmony.ps1 -SkipDependencyInstall -SkipBuild` 与完整 Debug 构建均通过）。

### 8.2 模拟器回归（ZhihuPlus_API23，127.0.0.1:5555，API 23）

已验证：升级安装保留旧数据默认自适应；四挡互切即时更新说明文案；选“流畅”后强杀进程重启正确恢复（不回写默认）；
设置搜索“沉浸”命中“外观与阅读体验”入口；首页底栏、问题页返回/操作胶囊在流畅/精美挡位渲染正常、无白条回归、无崩溃；
深色模式下四挡选中态与文字可读。截图见 `docs/ui-screenshots/immersive-material-*.jpg`。

**实测发现**：本模拟器 `getSystemMaterialTypes()` 返回 `[101]`（含 `IMMERSIVE=101`），即模拟器自身支持沉浸材质，
精美/轻柔按原挡生效、不显示降级提示属预期行为。

### 8.3 未验证项（设备条件不具备或属真机范畴，未宣称）

- “不支持 IMMERSIVE”与“能力查询失败”的设备端降级提示路径：模拟器无法复现，降级映射由 Hypium 单测覆盖。
- API 26 标题栏随挡位实时更新：标题栏材质门禁为 API 26+，API 23 模拟器不渲染材质分支，需 API 26 真机。
- 系统大字体/窄屏下的四挡段控表现、真机四挡视觉对比与长列表帧率/发热：需真机，无测量数据不下结论。
- 保存失败重试路径：本地无法模拟存储层失败，代码层就绪态门禁 + 重试语义已实现。
- 同页签内已挂载标题栏对挡位变化的实时刷新：样式函数已改为响应式传参，实际重渲染效果需 API 26 真机确认。
