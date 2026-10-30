# 设置搜索定位修复：实施与验收记录

日期：2026-10-29　分支：`feature/settings-search-location`　基线：`c9bf9019` 之后  
对应计划：`docs/plans/settings-search-location-fix-plan.md`  
验证环境：API 26 Debug 构建（target 26.0.0 / compatible 6.1.0(23)），Hypium 1124/1124 通过；设备验收在模拟器 `127.0.0.1:5555`（API 26，480×812vp 窄窗单栏）完成。

## 1. 实施内容

### 新增文件
| 文件 | 职责 |
| --- | --- |
| `pages/SettingsSearchTarget.ets` | 中立类型：`SettingsPaneId`（自 NavigationState 迁入）、`SettingsTargetKind`、定位请求/高亮信号快照、AppStorage 键名与读写助手 |
| `pages/SettingsSearchLocationState.ets` | 纯逻辑：滚动计划（钳制/零距离跳过）、滚动时长（280–500ms）、双次闪烁编排（160/200/100/160/200 ≈ 820ms）、`isRequestCurrent` 过期判定、`withAlpha` |
| `pages/SettingsSearchLocationRunner.ets` | 执行器：布局轮询（120ms，总预算 3s）→ `getComponentUtils` 测量 → `scroller.scrollTo` 缓出滚动 → onScrollStop 落点复核 + 一次有限纠偏 → 发布高亮；px→vp 密度换算；用户拖动/新请求/离页取消 |
| `components/SettingsSearchHighlight.ets` | `SettingsHighlightGroup` 提醒容器：包住既有分组卡片，overlay 只改主题色淡背景/描边 opacity，`hitTestBehavior(None)` 不阻断交互，有限阶段链驱动两个完整周期 |
| `test/SettingsSearchLocationState.test.ets` | 滚动钳制、零距离、时长区间、两个完整周期断言、alpha 拼接、请求过期 |

### 修改要点
- **索引**（`SettingsSearchIndex.ets`）：16 分类入口扩为 26 项，新增 10 个可定位细项（字号/行高/段间距/主题颜色/语速/音调/音色/广告/盐选/主题屏蔽阈值/手动 Cookie）；多词拆词匹配、别名（字体大小/行间距/朗读速度等）、四级优先排序（标题全等→包含→关键词→路径）、id 去重；`SettingsSearchEntry.id` 改为 string。
- **导航**（`SettingsNavigationState.ets`）：`SettingsPaneId` 迁出并 re-export；`paneForEntry` 收 string。
- **宿主**（`SettingsHomePage.ets`）：搜索结果点击走 `activateSearchEntry()`（与目录 `openEntry()` 区分）：`getFocusController().clearFocus()` 收键盘 → 发布请求快照 + tick（并广播取消信号复位残留动画）→ `selectPane`；详情内容挂 220ms 淡入 + 24vp 位移入场过渡。
- **详情页**（外观/朗读/过滤/关于/主题颜色/开发者实验室）：绑定各自 Scroller、内容根 id、行级锚点 id、分组高亮容器、`@StorageProp tick + @Watch + aboutToAppear` 双入口消费、`onScrollStart/Stop` 转发（用户拖动取消自动定位）；朗读/过滤页等 `loaded` 门控就绪后再测；主题屏蔽阈值关闭时回退 `filter_anchor_topic_enabled` 并 Toast“需先开启”。
- 独立根路由实例（`embedded=false`）一律不消费请求。

## 2. 构建与测试
- `pwsh scripts/verify-harmony.ps1 -SkipDependencyInstall`：API 26 Debug 构建 + Hypium **1124/1124** 通过（含更新的索引测试与新增定位状态测试）。
- 实施中修复的编译问题：`focusControl` 不在 Kit 导出（改用 `getFocusController().clearFocus()`）、`@BuilderParam` 默认值缺 `@Builder`、`ComponentUtils/ComponentInfo` 需从 `@ohos.arkui.UIContext`/`@ohos.arkui.componentUtils` 导入、Scroll 的 Scroller 走构造函数而非 `.scroller()`。

## 3. 设备验收（5555，截图存 `.tmp/shots/`）
| 场景 | 结果 |
| --- | --- |
| 输入“行高” | 结果随输入刷新，细项排分类前，清空按钮出现（before/seq）✅ |
| 点击细项 | 键盘收起 → 切外观页 → 平滑滚动 → 行高行落顶栏下沿，阅读卡片**恰好两个周期**闪烁（连拍 sq_3 亮/sq_4 亮二周期/sq_5、6 灭）✅ |
| 返回搜索目录 | 查询与结果保留、无键盘弹出 ✅ |
| 同页“段间距” | 落点与行高不同，精确到顶栏下沿（g3）✅ |
| 异步页“语速” | 等 loaded 后定位，语速行落点准确、语音卡片高亮，无 Loading 误闪（r1）✅ |
| 关于页“GitHub” | 定位到真实行，不打开网页/弹层（a1）✅ |
| “主题屏蔽阈值” | 本机开关为开，直接定位阈值行（t1）；关闭态回退前置开关 + Toast 的路径由纯逻辑测试覆盖，未在设备复现 ❗ |
| 别名“字体大小” | 命中“字号”细项 ✅ |

**过程中发现并修复的关键缺陷**：`getRectangleById` 返回 px 而 `scrollTo/currentOffset` 为 vp，首版定位越过一个分组（seq_6）；Runner 内统一除以 `densityPixels` 后定位准确。

## 4. 已知限制与后续
- 双栏（≥900vp）路径未在设备验收（模拟器为窄窗）；代码路径与单栏共用同一请求协议，左右栏职责按计划实现。
- 通知/系统更新/身份管理/内容屏蔽/屏蔽记录为分类落点（不滚动不闪烁）；按计划“实施时按页面清点”，后续可逐步补锚点。
- “减少动态效果”降级未实现（计划 §5.3 例外分支，需先核实 API 23 系统偏好读取）。
- 连点 A→B 取消、横竖屏重测为代码路径实现（runner 取消 + requestId 校验 + 高亮组复位），设备回归建议补录屏验收。
