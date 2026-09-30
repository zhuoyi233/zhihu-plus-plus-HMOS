# 沉浸光感挡位选择研究

研究日期：2026-09-30。代码基线：`d531e9b`；分支：`codex/immersive-material-levels`。

## 结论

本项目继续以 **HDS 的 `MaterialLevel.ADAPTIVE` 为默认值**，符合华为官方建议。若增加用户选择，可以提供“跟随系统、精美、轻柔、流畅”，另设“关闭”。手动选择精美或轻柔前必须查询设备材质能力；不支持 `IMMERSIVE` 时回落流畅或项目现有兜底。

HDS 的等级选择从 API 23 即可使用，无须为了选挡引入 API 26 的 `uiMaterial`。后者的设备等级只能查询，不能主动设置。两套接口中同名枚举的用途不同。[官方 HDS API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsmaterial)、[官方差异说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-faq)。

## 1. 先区分四个维度

| 维度 | 接口或来源 | 可选项与含义 |
| --- | --- | --- |
| 材质类型 | `hdsMaterial.MaterialType` | `NONE` 无材质；`ADAPTIVE` 跟随系统材质策略，当前默认沉浸材质；`IMMERSIVE` 指定沉浸材质 |
| HDS 材质等级 | `hdsMaterial.MaterialLevel` | 精美、轻柔、流畅、自适应，可通过组件参数设置 |
| 材质厚薄样式 | API 26 `uiMaterial.ImmersiveStyle` | 超薄、薄、常规、厚、超厚；影响透明、模糊、高光等表现，HDS 没有对应厚薄参数 |
| 系统沉浸光感偏好 | 用户的系统设置 | ArkUI 的最终表现还受用户系统偏好影响，不能把它直接映射为 HDS 的四个等级 |

因此，`GENTLE` 不能解释成 `THIN`，`SMOOTH` 也不等于关闭。类型与等级各有自己的 `ADAPTIVE`，代码中需要分别设置。[HDS API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsmaterial)、[ArkUI 简介](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-overview)。

## 2. HDS 四挡怎么选

下表的定义与能力限制来自官方文档；“本项目选择建议”是结合阅读应用场景的建议，尚未做挡位对照实测。

| 挡位 | 枚举值 | 官方定义 / 限制 | 本项目选择建议 |
| --- | --- | --- | --- |
| 自适应 `ADAPTIVE` | `10` | 系统按设备性能决定等级；官方推荐默认值 | 默认选项，适合全量用户 |
| 精美 `EXQUISITE` | `0` | 精美效果，性能开销较多；手动使用前查询 `IMMERSIVE` 支持 | 对视觉效果有偏好的用户主动选择，并验证持续滚动的帧率、发热 |
| 轻柔 `GENTLE` | `1` | 轻柔效果；手动使用前同样查询 `IMMERSIVE` 支持 | 提供另一种视觉选择；不能承诺固定省电比例或固定透明度 |
| 流畅 `SMOOTH` | `2` | 流畅效果，开销较少；不支持 `IMMERSIVE` 时官方建议使用 | 作为偏重流畅性的选择和手动高挡的降级目标 |

官方给出了等级名称、相对性能取向和设备能力检查规则，但没有给出各 HDS 挡位的固定模糊半径、透明度、GPU 开销或机型分界。不同组件的最终效果还取决于组件实现，不能用一处底栏截图代表全部标题栏和胶囊。[HDS API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsmaterial)、[HDS 使用指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-hds-component-material)、[差异说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-faq)。

### 能力判断的边界

- `getSystemMaterialTypes()` 返回支持的材质**类型**，不能告诉应用当前实际选中了哪个等级。
- HDS 当前公开接口中没有对应的等级查询函数；设置 `ADAPTIVE` 后，界面只能可靠显示“跟随系统”，不能伪装成已知的“当前精美”。
- `uiMaterial.getGlobalMaterialLevel()` 返回设备定义的算力等级，官方明确其不可修改；不能用它反推某个 HDS 组件当前的最终视效。
- API 版本达标不等于设备支持沉浸材质，不能仅凭 API 23/26 判断是否可开精美挡。

依据：[HDS API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsmaterial)、[uiMaterial API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-uimaterial)。

## 3. API 26 的厚薄选项

`uiMaterial.ImmersiveStyle` 的五种样式为 `ULTRA_THIN`、`THIN`、`REGULAR`、`THICK`、`ULTRA_THICK`。官方建议悬浮按钮和轻量提示采用较薄样式，常规内容采用常规样式，需要遮挡背景或加强层次的场景采用较厚样式。仍须满足对应组件的材质生效范围。

这些样式在高、中算力设备上有效；低算力设备只支持一种材质样式，设置厚薄不会产生对应差异。HDS 不提供对等选项，所以目前不能把项目设置做成“超薄玻璃 → 超厚玻璃”并声称有原生 HDS 参数支持。[uiMaterial API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-uimaterial)、[差异说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-faq)。

本项目最低兼容 API 23，按仓库约束继续使用 `@kit.UIDesignKit`，不向公共模块引入 API 26 专属 `uiMaterial`。

## 4. 当前项目接入情况

以下路径相对仓库根目录，行号基于本次代码基线。

| 位置 | 当前策略 |
| --- | --- |
| `entry/src/main/ets/pages/components/ZhihuHdsTabs.ets:67` | 首页底部导航：类型、等级均为 `ADAPTIVE`，`thermoCtrl: true` |
| `entry/src/main/ets/pages/components/ZhihuHdsTabs.ets:142` | `ZhihuHdsActionBar` 定义：相同策略 |
| `entry/src/main/ets/pages/components/MaterialCanvas.ets:40` | 复用玻璃画布：相同策略；`GlassCapsule` 另有组件模糊兜底 |
| `entry/src/main/ets/common/style/NavStyles.ets:48`、`:99` | 两种标题栏样式：类型、等级均为 `ADAPTIVE`；没有显式开启 `thermoCtrl` |
| `entry/src/main/ets/common/platform/HarmonyOSCapabilities.ets:12` | 查询设备是否支持 `IMMERSIVE` |
| `entry/src/main/ets/common/platform/HarmonyOSCapabilities.ets:26` | 标题栏保持 API 26 门禁；代码注释记录 API 23 真机白色遮挡问题 |

HDS 标题栏 API 本身从 API 23 提供材质参数，但本项目因既有渲染问题额外限制了使用范围。该限制应保留，不能因为“选挡支持 API 23”就移除。上述真机情况来自已有代码记录，本次未复测。

`thermoCtrl` 是单独的温控设置，不能与材质等级混为一谈。HdsTabs 文档定义其默认关闭；HdsNavigation 文档进一步说明，开启后在组件创建时若 `ThermalLevel > OVERHEATED`，关闭组件模糊效果。不能据此承诺所有材质会持续实时降挡。可把标题栏开启温控列为后续验证项。[HdsTabs API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdstabs)、[HdsNavigation API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsnavigation)。

## 5. 若增加应用设置，建议的实现范围

此节为后续方案，本次未改动应用代码。

1. 选项为“跟随系统（默认） / 精美 / 轻柔 / 流畅 / 关闭”；精美与轻柔仅在设备支持 `IMMERSIVE` 时允许生效。
2. 保持 `materialType: ADAPTIVE`，手动选择仅调整 `materialLevel`；关闭时使用 `MaterialType.NONE` 并显式提供中性背景，保证文字和图标可读。HDS 组件其他背景、光效是否仍保留需要实测。
3. 将“用户选择”和“实际生效策略”分开保存/计算。设备不支持时明确呈现降级结果；能力查询异常时继续走已有兜底。
4. 抽出统一材质参数解析方法，覆盖首页导航、复用画布、标题栏及操作栏，避免部分区域漏改。既有组件模糊兜底保留。
5. 设置经偏好存储持久化，并使用 AppStorage + `@StorageProp` 广播到已挂载页面；遵守项目对 HdsTabs 构建树的状态更新约束。
6. 各选挡控件继续读取 `resolvedThemeColor`；保留 API 23 标题栏门禁和已有温控设置。

若目的只是让玻璃更通透，先比较精美和轻柔的真机表现，并检查背景遮挡、画布范围与正文是否实际经过材质下方。升挡本身无法解决布局或遮挡问题。

## 6. 后续实测与性能关注点

选挡功能落地后至少比较：API 23 默认模拟器、支持沉浸材质的 API 23 真机、API 26 真机；覆盖深浅色、长列表连续滚动、图文交错背景、顶部返回胶囊、底部操作栏、评论输入和设置返回后的即时更新。

重点记录可读性、折射/高光差异、卡顿和持续使用发热；模拟器用于兼容与交互验证，真机用于视觉和功耗判断。关闭、能力查询失败、不支持 `IMMERSIVE` 的降级路径也需覆盖。

官方功耗指南强调控制材质面积与层数，避免材质嵌套、重复叠加模糊，以及把材质长期覆盖在视频/动图上。这些原则可作为本项目后续排查方向，具体收益须测量。[沉浸光感功耗优化](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-constraints)。

## 7. 资料与验证范围

- 通过 `devecocli docs search/read` 检索并阅读全文或相关章节：HDS 材质 API、HDS 沉浸光感指南、ArkUI 沉浸光感简介/FAQ/功耗优化、uiMaterial API、HdsTabs/HdsNavigation API。
- 同时检索华为官网；部分网页正文无法通过网页抓取读取，核心结论采用本机 DevEco 官方文档内容，保留上文官网链接便于人工查阅。
- 本机 SDK `hms/ets/api/@hms.hds.hdsMaterial.d.ets` 已核对四挡枚举、数值与 `@since 6.1.0(23)` 声明。
- 本次仅新增研究文档，未修改运行时代码，未运行构建、Hypium 或设备测试；不宣称挡位视觉和功耗已经验证。
