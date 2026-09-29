# 移除代码命名中的迁移阶段前缀：重构分析

日期：2026-09-28
分析基线：`302f04f0` 的工作区源码
状态：代码重命名已在 `codex/phase-prefix-removal` 分支实施；API 23 设备回归待补。

## 1. 目标与结论

将文件、类型、函数和变量命名中的迁移阶段编号，替换为稳定的业务或职责名称。例如：`P1Shell` → `AppShell`，`P1Destination` → `AppDestination`。

这里的“Px”指 [鸿蒙迁移计划第 7 节](../harmonyos-migration-plan.md#7-分阶段实施计划) 的 `P0`–`P6`，包括小写和名称中间的形式，如 `p1NavigationTest`、`decodeP1Destination`。像素单位 `px`、`heightPx`、`px2vp`、上游像素计算函数名称不属于清理对象。

建议以**名称重构**为主线，分批处理代码符号、资源名称和 UI 标识。保留现有四模块结构和页面职责；主界面拆分、导航架构调整、平台服务拆分另行评估，避免在名称调整中同时改变行为。

主要发现：

- 有 **7 个源码/测试文件**携带阶段前缀，完整映射见第 3 节。
- `P1Destination` / `P1DestinationName` 在 **36 个 `.ets` 文件**中出现，涉及 `core` 导出、`data` 日报解析、`entry` 页面和测试。统计包含定义、引用与注释，不能当作 36 个独立逻辑改动。
- `P4PlatformServices` 有 **8 个 `.ets` 引用文件**，除生产页面和平台实现外，还涉及选图、扫码测试。
- `entry/src/main/resources/base/element/float.json` 有 **25 个**阶段前缀资源名：12 个 `p1_`，13 个 `p3_`。当前文件内移除前缀后没有重名。
- 部分看似变量的名称实际上是状态通道字符串；另有 `p4-images` 等已被运行时使用的目录名，需要按兼容性处理。

以上为当前工作区静态盘点；实施前应重新扫描。正则结果可能包含注释、测试数据及加密向量，不能直接作为批量替换清单。

## 2. 范围与命名规则

| 对象 | 建议处理 | 原因 |
| --- | --- | --- |
| 文件名、导出类型、函数、变量 | 本轮主范围：按映射改名 | 使名称表达当前职责 |
| import/export、调用点、测试注册 | 与对应符号同批修改 | 保证构建与测试发现完整 |
| AppStorage、Provide/Consume 字符串 | 单独核对读写两端后改名 | 字符串不一定受编译器引用检查保护 |
| `$r()` 资源名、`.id()` UI 标识 | 作为后续清理批次 | 分别影响资源编译和 UI 定位 |
| 缓存目录、持久化键、序列化值 | 优先保留，登记兼容例外 | 改名可能影响升级前的数据 |
| 现行操作说明、源码职责注释 | 同步更新当前名称 | 避免新代码与操作手册脱节 |
| `docs/p0`–`docs/p5`、历史验收文档、阶段编号 | 保留原名和原始证据 | 阶段编号在这里表达真实历史 |
| 发布说明快照、fixture、签名/加密向量、上游参考 | 保留原始内容 | 文本相似不代表命名债务 |

统一规则：

1. 应用导航用 `AppDestination`，与已经存在的 `DeepLinkDestination` 区分。
2. 独立且清楚的业务名称直接去前缀，如 `TopLevelTab`、`ImagePickerPanel`。
3. 同一概念的文件、导出和函数采用一致命名；不保留长期 `P1*` 转发文件或别名。
4. 重命名前检查目标路径和导出是否重名，Windows 下额外检查忽略大小写的路径冲突。
5. 不改变枚举取值、数据字段、参数校验、返回栈算法、页面生命周期或组件装饰器语义。

## 3. 文件与符号映射

### 3.1 全部 7 个文件

下表路径相对仓库根目录；目标文件保留原目录。

| 当前文件 | 建议文件名 | 关联改动 |
| --- | --- | --- |
| `core/src/main/ets/navigation/P1Destination.ets` | `AppDestination.ets` | 类型、枚举、校验与解码函数；`core/Index.ets` 导出 |
| `entry/src/main/ets/pages/P1Shell.ets` | `AppShell.ets` | 组件声明、`Index.ets` 引入与构建、当前职责注释 |
| `entry/src/main/ets/pages/P1TopLevelTabs.ets` | `TopLevelTabs.ets` | 顶层标签枚举、辅助函数、页面与测试引用 |
| `entry/src/main/ets/pages/P4ImagePickerPanel.ets` | `ImagePickerPanel.ets` | 组件、选择回调类型、回答/想法编辑页引用 |
| `entry/src/main/ets/platform/P4PlatformServices.ets` | `PlatformServices.ets` | 8 个 import 路径；保留已有窄接口和 `ShareContracts` 导出 |
| `entry/src/test/P1Navigation.test.ets` | `AppNavigation.test.ets` | 测试函数、describe 名称、`List.test.ets` 注册 |
| `entry/src/test/P1Persistence.test.ets` | `Persistence.test.ets` | 测试函数、describe 名称、`List.test.ets` 注册 |

`P4PlatformServices.ets` 当前没有同名类：它定义 `PickedImage`、`ImagePicker`、`QrScanner`、`MediaPlaybackSource`、`MediaPlaybackService`、`SpeechService` 等接口，并重导出分享合同。改文件名即可，这些接口已表达职责，无需再加 `App` 前缀。

`P1Persistence.test.ets` 同时覆盖主题偏好和数据库升级计划，先改为 `Persistence.test.ets`。按偏好/数据库拆测试属于后续组织调整。

### 3.2 代码符号完整映射

| 原名称 | 新名称 |
| --- | --- |
| `P1Destination` | `AppDestination` |
| `P1DestinationName` | `AppDestinationName` |
| `isP1DestinationName` | `isAppDestinationName` |
| `decodeP1Destination` | `decodeAppDestination` |
| `P1StackEntry` | `NavigationStackEntry` |
| `findP1DestinationStackIndex` | `findAppDestinationStackIndex` |
| `p1DestinationIdentity` | `appDestinationIdentity` |
| `shouldPushP1Destination` | `shouldPushAppDestination` |
| `toP1Destination` | `toAppDestination` |
| `P1Shell` | `AppShell` |
| `P1TopLevelTab` | `TopLevelTab` |
| `p1TopLevelTabForDestination` | `topLevelTabForDestination` |
| `p1TopLevelTabLabel` | `topLevelTabLabel` |
| `isP1TopLevelTabIndex` | `isTopLevelTabIndex` |
| `P4ImagePickerPanel` | `ImagePickerPanel` |
| `P4ImagePickerSelectionCallback` | `ImagePickerSelectionCallback` |
| `p1NavigationTest` | `appNavigationTest` |
| `p1PersistenceTest` | `persistenceTest` |

测试描述字符串 `allowsEveryP4ContentLinkFamily`（`ShareService.test.ets`）建议改为 `allowsEverySupportedContentLinkFamily`，保留原有断言。

### 3.3 状态通道字符串

| 当前键 | 建议键 | 已确认的位置与处理要求 |
| --- | --- | --- |
| `p2ImagePreviewUrl` | `imagePreviewUrl` | `NativeContentDocument`、`CommentLayer` 写入；`ContentDetailPages`、`P1Shell` 订阅/清空。共 4 个文件、9 处，必须同批修改 |
| `p1PathStack` | `appPathStack` | 当前仅找到 `P1Shell` 的 `@Provide('p1PathStack')`；属性本身已叫 `pathStack`。实施前再次核对消费者，保留装饰器，仅改键 |

`p2ImagePreviewUrl` 当前用于进程内 AppStorage 通信。读写端全量更新后应验证正文和评论图片都能打开、关闭预览，关闭后正文滚动和返回操作正常。

不能借此将跨 feed 页通信改成 `@Builder` 传参或 `@Provide/@Consume`：仓库已记录 HdsTabs 下的更新限制。继续保留现有 AppStorage 广播机制。

## 4. 引用链与主要风险

### 4.1 导航是改动最集中的部分

入口关系：

```text
core/Index.ets → AppDestination（现 P1Destination）
  ├─ DeepLinkResolver / StartupDestinationChannel
  ├─ data 日报详情解析与仓库
  └─ EntryAbility / Index / AppShell / 各业务页面 / 导航相关测试
```

`StartupDestinationChannel.ets` 的文件名已经合适，但内部的 `P1StackEntry`、身份计算、栈查找、去重及深链转换函数都要改。只搜索以 `P1` 开头的名称会漏掉 `findP1DestinationStackIndex` 和 `shouldPushP1Destination`。

需要同步检查：

- `core/Index.ets`、`DeepLinkResolver.ets` 的路径引用。
- `EntryAbility.ets` 的冷启动/热启动目的地转换。
- `DailyStoryDetailDecoder.ets`、`DailyStoryRepository.ets`、`DefaultDailyStoryRepository.ets` 的跨模块类型。
- `AppStartup.test.ets`、`BackStackState.test.ets`、日报和通知跳转测试。

枚举字符串目前是 `'Home'`、`'Answer'`、`'Settings'` 等业务名称，保持原值。顶层标签的数字值、用户保存的底栏顺序和启动目的地也应保持原值；单纯符号重命名不需要数据库 schema 升级。

### 4.2 主界面与选图组件

`Index.ets` 是页面入口与生产依赖组合位置，内部构建 `P1Shell`。`main_pages.json` 当前注册的是 `pages/Index`，因此重命名 Shell 无需改动页面入口配置。

改名时保留 `@Component`、`@Builder`、`@BuilderParam`、`@State`、`@Watch` 与闭包结构。不能顺手改写 builder 调用形态，否则可能出现构建成功但组件不显示的问题。

图片选择面板与草稿缓存所有权相连。保留 `retainPreparedImages` 和恢复引用的处理，验证退出未保存编辑页、恢复已有图片草稿、取消选择等路径。

### 4.3 测试发现依赖文件名与注册函数

`scripts/verify-harmony.ps1` 的 `Get-RegisteredTestCount` 从 `List.test.ets` 读取 import 和函数调用，再解析被注册文件里的静态 `it()`。重命名必须同时改文件路径、import 标识符、注册调用和 describe 名称。

现有解析规则没有写死 `p1`，无需因改名调整脚本。应记录改名前后的注册套件及用例数，并要求数量相同，防止漏注册后“剩余用例全通过”掩盖覆盖损失。

## 5. 资源与 UI 标识清理

### 5.1 资源名

25 个 float 资源可保留语义后缀，统一删除 `p1_` / `p3_`：

| 资源类别 | 示例映射 | 数量 |
| --- | --- | --- |
| 字体、页边距、卡片、间距 | `p1_body_font_size` → `body_font_size`；`p1_spacing_small` → `spacing_small` | 12 |
| 段评弹层 | `p3_segment_quote_font_size` → `segment_quote_font_size` | 5 |
| 设置滑块 | `p3_settings_slider_thumb_width` → `settings_slider_thumb_width` | 8 |

同步修改全部 `$r('app.float.…')`。保留资源数值与单位，并检查其他资源限定目录是否存在同名定义。当前 base 文件内无目标重名，不代表未来新增资源不会冲突。

### 5.2 UI 标识

当前页面存在大量 `p1_`–`p5_` 标识及动态拼接前缀。建议采用 `<业务>_<控件/动作>`，例如：

- `p2_home_feed_list` → `home_feed_list`。
- `p3_comments_root_list` → `comments_root_list`。
- `p4_image_picker_select` → `image_picker_select`。
- ``p1_top_level_${…}_content`` → ``top_level_${…}_content``。

先收集 `.id()` 定义和动态生成函数，再生成映射，并检查去前缀后不同阶段是否产生同名。不能把同一名称的引用次数当成控件数量；可复用组件需要按页面/窗口区分定位范围。

UI ID 变化不会被普通类型检查充分覆盖，应同步搜索自动化脚本、测试、`AGENTS.md` 中的操作步骤。当前 `scripts/` 与 `.github/` 的所查脚本文本未发现阶段前缀命中，但外部脚本是否依赖旧 ID 尚未验证。

历史验收文档保留当时 ID，必要时加一条指向本映射的说明。现行操作说明必须以源码实际 ID 为准，例如首页重试动作应核对静态定义和拼接结果，不能照抄旧说明机械去前缀。

## 6. 需要保留或迁移的运行时名称

这三类运行时名称的后续迁移步骤、失败恢复和验收条件见 [运行时阶段名称安全移除计划](runtime-phase-name-migration-plan.md)。

### 6.1 `p4-images`：本轮保留

这不是普通变量名。已确认的关联包括：

- `ImageUploadContracts.ets` 的 `IMAGE_UPLOAD_TEMPORARY_DIRECTORY`。
- `SystemPickedImageFileStore.ets` 的目录创建、图片恢复、清理路径。
- `LocalDraftImageReferences.ets` 的受控路径校验。
- `DefaultImageUploadRepository.ets` 的上传 URI 白名单。
- 图片上传、草稿恢复、文件存储相关测试。

草稿持久化保存随机 `fileName` 和元数据，完整路径由当前缓存目录重建。仅把目录改成 `draft-images` 会让新版本到新目录查找旧图片；即使草稿 JSON 未变，旧图片仍可能恢复失败。

因此主范围保留 `p4-images` 的物理目录名，常量名称本身已经没有阶段前缀。若后续要求运行时路径也清零，应单独设计旧目录迁移：新写入使用新目录，恢复兼容旧目录；验证复制/移动成功后才清理旧文件；处理重复文件、部分失败和回滚。所有路径仍限定在应用受控缓存内，不能为兼容放宽到任意 URI。

### 6.2 其他例外

| 名称 | 所在位置 | 建议 |
| --- | --- | --- |
| `p4-share` | `ShareContracts.ets` 的 `SHARE_TEMPORARY_DIRECTORY` | 本轮保留。后续可独立改为 `share`，同时核对生产分享路径、临时文件清理与测试 |
| `probe:p1-production-opened-content` | `DatabaseProbe.ets` | 本轮保留。若改为 `probe:production-opened-content`，需要兼顾旧探针记录清理 |
| `P0-*` / `P4-*` 历史任务编号 | 迁移计划、验收记录及相关历史注释 | 作为历史引用保留 |

“完成名称重构”的标准允许这些明确登记的兼容例外。若目标扩大为所有运行时字符串也无阶段编号，应追加数据迁移任务和升级测试，不能直接扩大文本替换范围。

## 7. 建议实施顺序

| 批次 | 内容 | 验收重点 |
| --- | --- | --- |
| 准备 | 重新盘点、确认映射和目标冲突、记录测试注册数 | 原文件和引用范围可追溯 |
| 导航 | core 文件与符号、所有消费者、导航测试注册 | 深链、日报解析、导航身份与返回栈 |
| 页面与平台 | Shell、顶层标签、选图面板、平台合同文件、持久化测试改名 | 页面入口、标签切换、草稿选图、测试发现 |
| 状态通道 | 图片预览键、Provide 键 | 读写两端一致；跨页面恢复正常 |
| 资源与定位 | float 名称、UI ID 及当前操作说明 | 无资源漏改、无意外 ID 冲突、模拟器定位可用 |
| 收口 | 更新现行注释、核对剩余命中及兼容例外 | 无阶段代码符号和旧 import；历史记录可读 |

每批形成可构建的完整改动，不留下中间断开的引用。这里只划分实施和审查范围；提交、推送按仓库规则另行获得用户当次明确指令。

## 8. 验证与完成标准

### 8.1 静态检查

在仓库根目录使用 `rg` 定位候选，再人工按本方案分类：

```powershell
# 当前受版本控制的阶段命名路径；历史文档命中按例外处理。
git ls-files | rg '(^|/)[Pp][0-6][^/]*$'

# 首字母、中间位置、小写和字符串键候选。
rg -n '\b[Pp][0-6][A-Za-z_]|[A-Za-z]P[0-6][A-Z]' core/Index.ets core/src data/src entry/src reader/src -g '*.ets'

# 资源、UI 标识、运行时路径及现行工具说明。
rg -n '\bp[0-6][_-]|p1PathStack|p2ImagePreviewUrl' entry/src core/src data/src reader/src scripts .github AGENTS.md

git diff --check
```

宽范围正则只用于发现候选。加密向量、fixture、历史任务编号和兼容目录可能继续命中；最终依据明确映射和例外清单验收，不以全库 `P[0-6]` 零命中作为标准。

还需核对全部新 import 文件存在、`core/Index.ets` 对外导出完整、测试注册数量一致，以及重命名 diff 中没有混入业务逻辑变化。

### 8.2 构建与测试

代码实施时按仓库规定顺序，在 PowerShell 7 中运行：

```powershell
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -SkipBuild
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall
```

以脚本动态统计的用例数为准，记录实际结果。重点保留导航、返回栈、启动、日报、持久化、选图、草稿和分享已有断言。纯改名无需新增镜像测试；若实施运行时目录迁移，再增加旧数据恢复、失败重试与安全路径测试。

### 8.3 设备回归

默认设备为 `ZhihuPlus_API23`（`127.0.0.1:5555`），按仓库操作约定优先验证最低兼容 API 23；构建目标为 API 26：

1. 覆盖安装后冷启动，确认主题、登录态、底栏顺序与启动目的地仍可恢复。
2. 首页、关注、热榜、日报、历史、收藏和设置切换，验证返回栈及登录后的信息流刷新。
3. 知乎深链冷/热启动到问题、回答、文章，验证去重、返回和日报跳转。
4. 从正文和评论打开图片预览，再关闭预览，验证滚动、手势与返回。
5. 恢复旧版本保存且图片文件仍存在的草稿；选图、移除、保存、取消及退出编辑页，确认缓存所有权行为一致。
6. 用新 UI ID 获取布局和定位控件；保持现有发布确认流程，验证无需实际发布内容。

### 8.4 完成清单

- [x] 7 个文件完成重命名，旧路径无活跃 import/export。
- [x] 第 3 节代码符号及测试注册全部更新，没有长期旧名称别名。
- [x] 状态通道两端一致，资源引用完整，UI ID 冲突已检查。
- [x] 枚举取值、持久化字段、路径安全约束及已有行为保持一致。
- [x] 剩余阶段字符串均能归入历史记录、测试数据或兼容例外。
- [x] 两步验证通过，测试发现数量不减少。
- [x] API 23 签名安装、启动、顶层标签切换、问题/回答/文章深链、返回栈、日报详情和朗读设置路由已实测并记录。
- [x] API 23 登录后信息流、问题/回答/文章正文、正文与评论图片预览、收藏和历史入口完成回归。
- [x] API 23 选图预览、多图、移除与带图片草稿保存已实测（见第 12 节）。
- [x] 新保存的双图草稿在退出编辑器后重新打开，标题、正文和两张预览均恢复（见第 13 节）。
- [ ] 升级前已有图片草稿、升级前设置与登录态保留完成验证；设备没有事前快照或旧草稿（见第 11–13 节）。

## 9. 本次分析的验证记录

本段记录初始分析阶段完成的盘点；实施和验证状态见第 10 节。

## 10. 实施与验证记录

日期：2026-09-29
分支：`codex/phase-prefix-removal`
基线提交：`e3ef21cb`

- 完成第 3 节的 7 个文件重命名、符号和测试注册更新，并将图片预览与导航状态键改为稳定名称。
- 完成 25 个 float 资源名及阶段化 UI ID 清理；更新当前操作说明中的 Shell 名称和首页重试 ID。`p4-images`、`p4-share`、探针键和历史文档按兼容规则保留。
- 基线和重构后的测试注册均为 84 个套件、696 个 Hypium 用例。
- `pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -SkipBuild` 通过，Hypium 696/696。
- `pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall` 通过，HAP 校验为 target API 26、compatible API 23，Hypium 696/696；产物为 `ZhihuPlusPlus-HMOS-v0.5.6-unsigned.hap`。
- `git diff --check` 通过；活跃源码中旧文件路径、符号、状态键及旧 float 名称无命中，资源引用无缺失，float 定义无重复。
- API 23 设备：已确认 `ZhihuPlus_API23`（`127.0.0.1:5555`）系统 API 版本为 23。CLI 登录后生成本地调试签名，完整构建成功并安装 `ZhihuPlusPlus-HMOS-v0.5.6-signed.hap` 覆盖设备原 v0.5.1；未卸载旧应用。签名配置已设为 skip-worktree。
- API 23 手动检查：冷启动进入 v0.5.6 更新内容页；首页、关注、热榜、日报、“我的”标签切换正常，新 ID（如 `top_level_daily_content`、`channel_daily_9792867`）可见。日报列表加载内容，首条可进入回答详情并返回列表；问题、回答、专栏文章深链分别进入对应详情，连续返回回到原“我的”页；朗读设置入口可打开。
- 覆盖升级后的首次启动登录态不可用；在设备上重新登录后，首页与关注/热榜内容恢复。后续登录态回归结果见第 11 节。

## 11. 登录后 API 23 回归

日期：2026-09-29

- 首页 `home_feed_list` 加载推荐卡片，点 `home_refresh_fab` 后列表换成新卡片；关注推荐 `channel_following_recommend_list`、热榜 `channel_hot_list` 均加载内容。日报列表已在登录前加载。
- 从热榜问题进入真实问题详情，正文和回答可见；进入回答详情再连续返回至问题与热榜。从关注推荐进入文章详情，正文可见并可返回。收藏夹 `collections_list` 与阅读历史 `read_history_list` 均可打开。
- 问题正文图片打开 `image_preview_overlay` 后实际图像可见；返回键关闭预览，问题详情保持，继续滑动能显示下一张回答卡片。问题评论列表中一张评论图片也可打开预览；返回后预览消失并回到问题详情，评论弹层在预览期间收起。
- 想法草稿箱显示当前账号没有可恢复的草稿，故无法实测升级前图片草稿恢复。想法编辑页的系统相册能打开；分别选择两张图片后，页面均提示“无法安全读取所选图片，请重新选择”，未出现 `image_picker_preview_0`，因而无法验证移除、保存和恢复。设备日志显示选图回调成功，随后 `fileIo.copyFile` 返回错误码 2；该复制实现所在 `SystemPickedImageFileStore.ets` 在本轮重构中未改，旧版是否同样失败尚未实测。
- 系统相册取消选择后显示“已取消选择，未上传图片”；退出空编辑页后草稿箱仍为空。升级前主题设置、底栏顺序及有效登录态没有事前快照，不能据此断言这些状态保留。早前近期日志出现 `subscribeHoldingHand failed, code=31500002`；当时查询的最新崩溃记录仍为 9 月 18 日的 v0.5.0。
- 将应用进程强制停止后，以已加载成功的问题链接冷启动，直接进入问题详情并加载正文；再次热启动同一链接后，一次返回即回到首页，未观察到重复问题页叠加。

## 12. API 23 选图修复与复测

日期：2026-09-29

- 系统 Photo Picker URI 由 `fileIo.open` 成功读取，但 `fileIo.copyFile` 的字符串路径参数返回错误码 2。在 `SystemPickedImageFileStore.ets` 中改为打开源 URI 和应用缓存目标文件，使用两个文件描述符复制；复制前核对源文件大小，复制后继续执行原有的大小、格式与图像尺寸校验及失败清理。缓存目录仍为 `p4-images`。
- 按仓库规定顺序重跑两步验证：均通过，Hypium 696/696；完整构建的签名 HAP 为 target API 26、compatible API 23，并成功覆盖安装到 `127.0.0.1:5555`，未清理设备应用数据。
- 真实相册选中一张 JPEG 后，编辑页显示“已安全准备 1 张图片”、`image_picker_preview_0` 和图片元数据；点“移除”后预览消失。再次选择两张图片，页面显示两个预览和“已安全准备 2 张图片”。
- 带标题和正文的双图草稿可保存，并在草稿箱出现测试条目 `API23_picker_smoke`。标题或图片单独保存时页面报“发布失败，草稿已保留”，填写正文后可保存。当时重新打开这个草稿时编辑页为空；检查发现想法编辑页只初始化发布状态，未调用 `DraftRepository.load()`。后续修复和再验证见第 13 节。测试草稿仅留在设备本地草稿箱，未发布到知乎。

## 13. 草稿恢复与缓存所有权修复

日期：2026-09-29

- 想法编辑页在挂载选图面板前读取当前账号和草稿键对应的 `DraftRepository` 记录。加载成功后恢复标题、加密正文、已上传图片、受控本地图片引用与话题；损坏草稿拒绝进入编辑。恢复后的本地引用仍只由随机文件名重建应用缓存路径，不读取原 Photo Picker URI。
- 编辑页初始准备阶段不再先挂载空的选图面板。面板的 `retainPreparedImages` 改为响应式 `@Prop`，沿用原有“当前内容含本地图片引用就保留”的判断。此前面板离开时仍持有旧的 `false` 值，会误删已保存草稿的图片，导致重新打开后图片 `onError`。
- 新增两条回归用例，分别覆盖混合图片草稿恢复与受控文件引用重建。按顺序运行两步验证均通过，当前为 84 个套件、698/698 Hypium 用例；签名 HAP 为 target API 26、compatible API 23。
- API 23 模拟器覆盖安装后，在原测试草稿里重新选取两张图片并保存；退出后从草稿箱重新打开，`API23_picker_smoke` 标题、正文和 `image_picker_preview_0`/`image_picker_preview_1` 均出现，页面显示“已安全准备 2 张图片”。本机已登录会话在这几次覆盖安装后继续可用。升级前已有草稿、主题和底栏顺序没有基线，仍不能据此断言其升级保留情况。
- 当时空正文的图片或标题草稿保存仍会失败；后续修复与复测见第 14 节。设备上的 `API23_picker_smoke` 测试草稿仍留在本地草稿箱；未触发正式发布。

## 14. 空正文草稿保存修复

日期：2026-09-29

- `DraftCipher` 原实现将空 HTML 编码成零长度数据交给 AES-GCM `update`，导致 API 23 上仅标题或仅图片的草稿保存失败。改为空正文使用草稿 HTML 校验明确禁止的 NUL 作为加密前哨兵；解密完成后仅将该哨兵还原为空字符串，信封版本、密钥和已有非空草稿格式不变。
- 按顺序运行 `verify-harmony.ps1` 的 `-SkipBuild` 与完整构建两步，均通过，Hypium 698/698；签名 HAP 为 target API 26、compatible API 23。覆盖安装到 `127.0.0.1:5555`，未清理应用数据。
- API 23 模拟器上，新建仅标题 `API23_empty_body_title` 草稿，正文保持空白；保存后草稿箱出现该条，重新打开可恢复标题且正文仍为空。另新建仅一张 JPEG、标题和正文均为空的草稿；草稿箱显示“未命名想法”，重新打开仍可见 `image_picker_preview_0`。
- 旧测试草稿 `API23_picker_smoke` 的标题与非空正文仍能恢复；本次打开时旧两张图片未恢复，选图组件显示“无法安全读取所选图片，请重新选择”。未确认该旧草稿的图片缓存何时丢失，不将其计入本修复的图片保留验证。上述测试草稿均仅保存在模拟器本地，未发布。
