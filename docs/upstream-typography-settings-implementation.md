# 排版自定义(字号/行高/段间距/可拖动滚动条)迁移实现文档

> 状态:**已实现**(编译 + 590 用例全过 + API 23 模拟器实测,见 §8)。
> 上游参考:`refs/remotes/upstream/master`
> (可用 `git worktree add --detach .worktrees/_ref refs/remotes/upstream/master` 挂出,下文路径均相对该根)。
>
> 落地时对设计稿的四处修正(细节见对应小节):
> 1. 字号档位数是 **23 档**而非 24(`50..120 step 5` 共 15 + `130..200 step 10` 共 8),
>    滑块用 ArkUI 的 `step` 而非 Compose 的 `steps`(§2.1、§5.3);
> 2. 设计稿的"内容总高 = max(已见滚动量 + 视口)"会使进度**恒为 100%**(滚动量本身就是最大值),
>    改为"实测块高估算 + 已滚范围下界 + 触底校准"(§5.4、§6 决策 3);
> 3. 设置页三值用 `@StorageProp` 而非页面 `@State`,并新增 `ReaderTypography.ets` 承载
>    百分比→像素映射(可单测,供宿主与行内公式子组件共用)(§5.3、§7);
> 4. 滚动条的"整页覆盖层 + `hitTestBehavior(None)`"与"alpha=0 时 `if`/`Visibility.None`
>    不渲染"两条在真机上分别会**吃掉正文滚动**与**永久丢命中**,改为"12vp 右对齐子节点
>    + 节点常驻 + `hitTestBehavior` 开关",实测拖动链路可用(§5.4、§6 决策 6)。

## 1. 目标

对齐上游"排版自定义"能力:

1. 正文**字号**调节(百分比,档位吸附);
2. 正文**行高**调节(百分比);
3. 正文**段间距**调节(百分比);
4. 正文页**可拖动滚动条**(自绘、可拖动定位、自动淡出)。

设置入口对齐上游形态:全局设置页滑块(上游为 `AppearanceSettingsScreen` 的"阅读"分组)。
不在详情页底栏加快捷面板(上游无此交互)。

## 2. 上游行为基线(逐项核对过源码)

### 2.1 设置模型

定义于 `shared/src/commonMain/kotlin/com/github/zly2006/zhihu/ui/subscreens/AppearanceSettingsScreen.kt`
(L127-162 常量区、L616-692 "阅读"分组 UI),持久化走跨平台 `SettingsStore` →
Android SharedPreferences(文件 `com.github.zly2006.zhihu_preferences`):

| 设置项 | 键 | 默认 | 范围 | 步进/吸附 |
|---|---|---|---|---|
| 字号 | `contentFontSize` | 100(%) | **23 档**:`50..120 step 5`(15 档)+ `130..200 step 10`(8 档)(无 125) | 吸附到档位数组 |
| 行高 | `contentLineHeight` | 160(%) | 100..300 | 10% 一档(20 个区间) |
| 段间距 | `contentBlockSpacing` | 100(%) | 0..300 | 10% 一档(30 个区间) |

细节:上游读取旧值时会 coerce 到最近档位并**回写**;滑块拖动中**即时写盘**(非松手才写)。
等距时上游 `minBy` 取**首个最小项**(即较小档),本实现保持一致(`125 → 120`、`135 → 130`)。

### 2.2 消费端(同一套键全局生效)

- **正文渲染(默认路径)** `shared/.../markdown/RenderMarkdown.kt` L318-388:
  三个百分比换算成系数传给渲染器:
  - 传统 Markdown 渲染器:`scaledFontSize = 16sp * fontSize / 100`,
    `lineHeight = scaledFontSize * lineHeight / 100`,
    `blockSpacing = 12.dp * blockSpacing / 100`(段间距是**主题级 Dp 乘法缩放**,非 CSS/Span 注入);
  - Tiqian 渲染器:`fontSizeScale = fontSize/100f`、`lineHeightFromFontSize = lineHeight/100f`、
    `blockSpacingScale = blockSpacing/100f`。
  - 标题、公式等一并按 `fontSize/100` 缩放(如 mathFontSize = 18f * scale)。
- **评论正文** `shared/.../ui/CommentScreen.kt` L1367-1376:`16.sp * fontSize/100`,行高同链路。
- **信息流卡片标题** `shared/.../ui/components/FeedCard.kt` L295-310:按 `fontSize/100` 缩放。
- **Legacy WebView 路径** `shared/.../androidMain/.../WebviewComp.kt`:注入
  `<style> body { font-size: N%; line-height: lh/100 } </style>`(本项目无此渲染路径,不适用)。

### 2.3 可拖动滚动条

`shared/src/commonMain/kotlin/com/github/zly2006/zhihu/ui/components/VerticalReadingProgressBar.kt`
(211 行,纯 Compose 自包含),接入于 `ArticleScreen.kt` L1169-1179(右缘悬浮,
top = 状态栏+64dp、bottom = 导航条+96dp、end=2dp)。核心逻辑:

- **拇指高度** = `视口高 × (视口高 / 内容总高)`,下限 24dp:
  ```kotlin
  contentHeight = viewportHeight + maxScroll
  thumbHeight = viewportHeight * (viewportHeight / contentHeight)
      .coerceIn(minThumbHeightPx, viewportHeightPx)
  ```
- **拇指偏移** = `(视口高 − 拇指高) × progress`,`progress = scrollY / maxScroll`。
- **拖动回写滚动**:`draggable` 累加 delta → 换算新 offset →
  `scope.launch { scrollState.scrollTo((newProgress * maxScroll).toInt()) }`,
  `startDragImmediately = true` 保证按下即开始拖动。
- **自动淡出**:滚动/拖动停止后延迟 `1200ms` 淡出(出现 120ms / 消失 260ms 动画);
  `alpha <= 0 且未在拖动` 时组件不参与组合。
- **视觉**:轨道区宽 12dp(轨道 2dp `outlineVariant alpha0.45` 圆角条),
  拇指 4dp 宽 `primary alpha0.88` 圆角条。
- 上游**没有**滚动条开关设置项,始终渲染。

## 3. 鸿蒙侧现状

- 正文渲染:**HTML 解析成块 → 原生 List 自绘**(无 RichText/WebView)。
  详情页容器 `entry/src/main/ets/pages/ContentDetailPages.ets`(`ContentDetailPage`
  被问题/回答/文章三个壳包装),正文组件 `entry/src/main/ets/pages/NativeContentDocument.ets`:
  - L691 `List({ space: 12, scroller })` —— **段间距就是这个写死的 12**;
  - L721 `.scrollBar(BarState.Off)` —— 当前无滚动条;
  - L807-810 普通段落 `.fontSize($r('app.float.p1_body_font_size')).lineHeight(30)`;
  - L416-417 含行内公式段落同款字号/行高;
  - L785-788 标题 `.fontSize($r('app.float.p1_heading_font_size'))`(20fp);
  - L601-620 问题页折叠正文内层 Scroll(仅测量用,不需排版联动);
  - L743 已有 `.onDidScroll`(顶栏折叠/上下边界信号),可复用为滚动条显隐驱动。
- `$r('app.float.p1_body_font_size')` 是编译期资源,**不能动态改值**;字号自定义必须改为数值。
- 持久化模式(项目既有两层,新设置照抄即可):
  - `data/src/main/ets/preferences/AppPreferencesStore.ets`(key 常量 L19-33、
    load/save 模板如 `loadAnswerDoubleTapAction` L210-232 / `write...` L358-369,
    saveQueue 串行写盘);
  - 运行时广播走 **AppStorage 同名 key**,消费端 `@StorageProp(...)`;页面侧 restore/save
    成对 helper(如 `ContentDetailPages.ets` L1525-1549、`P1Shell.ets` L2194-2222)。
- 设置页:`P1Shell.ets` `settingsPage()` L1135,"通知与外观"卡片 L1182 起
  (主题模式、双击回答动作),之后是"关于与诊断"。

## 4. SDK 能力核查结论(影响方案)

在本机 SDK(`%USERPROFILE%\App\Huawei\DevEco Studio\sdk\default\openharmony\ets`,API 26)核实:

- `Scroller` **没有** `getScrollerInfo()` / 最大滚动距离 API(仅 `currentOffset()`、
  `getItemRect()` 等;后者对 LazyForEach 未渲染项返回 undefined);
- `onScrollBarUpdate`(可直接拿 scrollableDistance 的回调)**只有 Grid 支持,List 不支持**。

⇒ 可拖动滚动条的"内容总高"**无法直接读取,需自估**(方案见 §5.4)。

`Slider`(API 7+)、`PanGesture`、`animateTo`、`@StorageProp` 均远低于 API 23 兼容线,无风险;
不涉及 `uiMaterial`,API 23 安全。

## 5. 实现方案

### 5.1 数据层(AppPreferencesStore.ets)

新增三个 key(与上游键名一致,存储 Int 百分比):

```ets
// 键与语义对齐上游 AppearanceSettingsScreen 的排版偏好(Int 百分比)。
const CONTENT_FONT_SIZE_KEY = 'contentFontSize';         // 默认 100,档位 50..120 step5 + 130..200 step10
const CONTENT_LINE_HEIGHT_KEY = 'contentLineHeight';     // 默认 160,范围 100..300 step10
const CONTENT_BLOCK_SPACING_KEY = 'contentBlockSpacing'; // 默认 100,范围 0..300 step10
// 同文件另导出默认值 / 滑块边界与步进常量,供设置页复用:
// DEFAULT_CONTENT_FONT_SIZE|LINE_HEIGHT|BLOCK_SPACING、
// CONTENT_LINE_HEIGHT_MIN|MAX、CONTENT_BLOCK_SPACING_MIN|MAX、CONTENT_TYPOGRAPHY_STEP。
```

配套纯函数(可单测,`ReaderTypography.test.ets` 覆盖):

```ets
export interface ReaderTypography { fontSize: number; lineHeight: number; blockSpacing: number }
export function contentFontSizeLevels(): number[]        // 23 档,见 §2.1
export function defaultReaderTypography(): ReaderTypography      // 100/160/100
export function decodeContentFontSize(value: preferences.ValueType): number
  // 非数字/NaN → 100;否则 clamp 到档位区间后吸附最近档(等距取较小档,对齐上游 minBy)
export function decodeContentLineHeight(value: preferences.ValueType): number
  // 非数字/NaN → 160;否则 round 到 10 的倍数并 clamp 100..300
export function decodeContentBlockSpacing(value: preferences.ValueType): number
  // 非数字/NaN → 100;否则 round 到 10 的倍数并 clamp 0..300
export function normalizeReaderTypography(value: ReaderTypography): ReaderTypography  // 三值各自吸附/回退
```

`loadReaderTypography(): Promise<ReaderTypography>` 一次读三个
(减少 getPreferences 往返),`saveReaderTypography(...)` 一次写三个 + flush,
均按既有 saveQueue 模板(参照 `loadAnswerDoubleTapAction`/`writeAnswerDoubleTapAction`)。

`data/Index.ets` 已是 `export * from '.../AppPreferencesStore'`,新增类型与函数
自动导出,**无需改动**。

### 5.2 消费端(NativeContentDocument.ets)

新增状态(AppStorage 键名与持久化键同名,`@Watch` 用于排版变化时清理块高实测缓存):

```ets
@StorageProp('contentFontSize') @Watch('onTypographyChanged') private fontSizePercent: number = 100;
@StorageProp('contentLineHeight') @Watch('onTypographyChanged') private lineHeightPercent: number = 160;
@StorageProp('contentBlockSpacing') @Watch('onTypographyChanged') private blockSpacingPercent: number = 100;
```

派生值(**默认视觉零变化**的映射,见 §6 决策 1)统一走新增模块
`entry/src/main/ets/pages/ReaderTypography.ets`(纯函数,可单测;宿主与行内公式子组件共用):

```ets
// ReaderTypography.ets
readerBodyFontSize(fontSizePercent)                      // 16 × 字号%,默认 16
readerBodyLineHeight(fontSizePercent, lineHeightPercent) // 字号 × 1.875 × (行高% / 160),默认 30
readerBlockSpacing(blockSpacingPercent)                  // 12 × 段间距%,默认 12
readerHeadingFontSize(fontSizePercent)                   // 20 × 字号%,默认 20
```

单位与改造前同义,故默认档逐像素不变:字号/行高返回值交给 `Text.fontSize`/`Text.lineHeight`,
ArkUI 传 number 时单位是 **fp**(旧的 `app.float.p1_body_font_size` = 16fp、`.lineHeight(30)` = 30fp);
段间距返回值交给 `List`/`Column` 的 `space`,number 单位是 **vp**(旧的 `space: 12`)。
因此**未出现"资源 fp → 数值 vp"的系统字体缩放回归**。

改动点:

| 位置 | 现状 | 改为 |
|---|---|---|
| `List({ space })` | `space: 12` | `space: this.blockSpacingVp()` |
| 行内公式段落(ContentInlineFormula) | `$r('app.float.p1_body_font_size')` / `.lineHeight(30)` | `.fontSize(readerBodyFontSizeVp(...))` / `.lineHeight(readerBodyLineHeightVp(...))` |
| 标题 | `$r('app.float.p1_heading_font_size')` | `.fontSize(this.headingFontSizeVp())` |
| 普通段落 | 同正文段落 | `.fontSize(this.bodyFontSizeVp())` / `.lineHeight(this.bodyLineHeightVp())` |
| 问题页折叠正文内层 Column | `Column({ space: 12 })` | `Column({ space: this.blockSpacingVp() })` |

注意(实测结论):

- `ContentInlineFormula` 未走"由调用方传 `@Prop`",而是**内部加同款 `@StorageProp`**
  (与宿主同源,少动调用方);行内公式 `ImageSpan` 高度 24 未随字号缩放(与上游
  mathFontSize 缩放不完全对齐),列为二期。
- **LazyForEach 刷新实测有效**:可见项属性绑定直接引用 `@StorageProp`,字号/段间距
  变化后列表项即时重排,**未**需要 `item.id + '@' + styleVersion` 的兜底方案。
- **`List` 的 `space` 动态刷新实测有效**:`space: this.blockSpacingVp()` 在段间距
  变化后即时生效,**未**需要 `space: 0` + 逐块 `margin` 的兜底方案。
- 问题页折叠正文的内层 Scroll(`collapsibleBodyViewport`)按自然高测量,字号变化后
  `onAreaChange` 会自动回填 `naturalHeightVp`,无需额外处理。
- 滚动条(见 §5.4)挂在同一 build Stack 内,问题/回答/文章三页同时获得。

### 5.3 设置 UI(P1Shell.ets)

入口:`settingsPage()` "通知与外观"卡片之后新增**"阅读"**分组卡片(对齐上游命名),
内含三行,每行 = 标题 + 当前值描述 + Slider(仿上游 `SettingItem + bottomAction Slider`):

```
字号        调整内容文字大小 (100%)                    id=p3_settings_content_font_size
行高        调整内容行间距 (160%)                      id=p3_settings_content_line_height
段间距      调整正文段落和块级内容间距 (100%)          id=p3_settings_content_block_spacing
```

- **字号 Slider 用档位索引**:`Slider({ value: 档位下标, min: 0, max: 档位数-1 = 22, step: 1 })`,
  value 绑定 `contentFontSizeLevels().indexOf(当前值)`,`onChange` 里 `Math.round` 吸附索引 → 档位值。
  ArkUI **没有** Compose 的 `steps`(中间刻度点数)属性,数值吸附由 `step` 决定,
  刻度点显隐用 `.showSteps(true)`——这是设计稿写 `min=0/max=23/steps=22` 的对应改法。
  其余两个 Slider 直接 `min/max/step`(100..300 step 10、0..300 step 10),
  `onChange` 里过一遍 `decodeContentLineHeight` / `decodeContentBlockSpacing` 完成吸附+clamp。
- 写入模式照抄 `selectAnswerDoubleTapAction`:
  `AppStorage.setOrCreate(键, 值)`(即时生效,详情页若开着实时联动)→
  单实例 `AppPreferencesStore.saveReaderTypography(...)` 落盘;失败静默(选择已生效)。
  **单实例**是设计稿未写明但必需的一点:滑块拖动过程中每次 `onChange` 都写盘(照上游),
  只有复用同一个 store 实例才能让 `saveQueue` 真正串行化。
- 三值用 `@StorageProp` 而非页面本地 `@State`(与同文件 `answerDoubleTapAction` 一致):
  `restoreReaderTypography()` 挂进 `aboutToAppear` 的 restore 链,load 后 `AppStorage.setOrCreate`
  即驱动 UI;读取失败保持默认 100/160/100(与改造前视觉一致)。

### 5.4 可拖动滚动条(新组件 ReadingProgressBar.ets)

新文件 `entry/src/main/ets/pages/components/ReadingProgressBar.ets`
(目录参照 `MaterialCanvas.ets`),自包含、不依赖页面状态,签名:

```ets
@Component
export struct ReadingProgressBar {
  scroller: Scroller = new Scroller();              // 与正文 List 共享,拖动时直接 scrollTo 回写
  @Prop @Watch('onBarInputChanged') viewportHeightVp: number;  // 宿主 List 的 onAreaChange 回填
  @Prop @Watch('onBarInputChanged') contentHeightVp: number;   // 宿主维护的估算值(见下)
  @Prop @Watch('onBarInputChanged') scrollYVp: number;         // 宿主 onDidScroll 每帧回填
  @Prop topInsetVp: number; @Prop bottomInsetVp: number;       // 轨道上下留白(避开顶栏/底栏)
  onSeekStateChange?: (dragging: boolean) => void;             // 拖动起止通知宿主(见下)
  // 内部:@State alpha/dragging/dragProgress、PanGesture、1200ms 淡出 setTimeout
}
```

宿主侧(NativeContentDocument):

- build 的 Stack(`alignContent: Alignment.TopEnd`)末尾加 `ReadingProgressBar({...})`,
  `.width(12)` + `.margin({ right: 2 })` 实现右缘悬浮(正文 List 是 100%×100%,不受
  alignContent 影响);轨道上下留白取固定 `topInsetVp = 4` / `bottomInsetVp = 96`
  (避开底部悬浮操作栏,底栏实际占位与 `contentEndOffset(100)` 同量级)。
- **不用整页覆盖层**(设计稿原写的 `Row().width('100%')` + `hitTestBehavior(None)`):
  实测整页层即使标 `None` / `Transparent` 也会进入命中链,中央拖动正文列表滚不动;
  改成"宽 12vp 的右对齐子节点"后,Stack 内重叠区域默认只命中最上层节点,
  右缘 12vp 归进度条、其余区域照常命中正文,互不干扰。
- `List` 加 `.onAreaChange` 回填 `viewportHeightVp`;
- 复用现有 `.onDidScroll`:每帧回填 `scrollYVp = currentOffset().yOffset` 并刷新内容总高估算;
- `onSeekStateChange(true)` 时宿主调 `updateBottomEdge(false)` + `updateTopEdge(false)`:
  拖动期间正文由 `scrollTo` 驱动,回答页的 `parallelGesture` 过滑手势**不会**被滚动条的
  PanGesture 阻断,若不屏蔽,贴底时向上拖滚动条会被误判为"下一答"过滑而误切换回答。

**内容总高估算(设计稿在此处有误,已改)**:设计稿写"每帧
`contentHeightVp = max(contentHeightVp, yOffset + viewportHeightVp)`",但单调下滑时
`yOffset` 恒为历史最大值,推出 `maxScroll = yOffset`,**进度恒为 100%**。落地方案改为:

1. 每个正文块 `ListItem` 挂 `.onAreaChange` 实测块高(页头/页脚三个固定槽位另记),
   累积 `Σ实测块高 + 实测块数 × 块间距` 与实测均值;
2. `估算总高 = Σ实测块高 + 未测块数 × 实测均块高 + 页头页脚实测高`,
   并取 `max(估算, yOffset + viewportHeightVp)` 兜底(已滚范围是硬下界,保证拇指不越出轨道);
3. `.onReachEnd` 时把 `contentHeightVp = yOffset + viewportHeightVp` 记为**精确值**并优先采用,
   直到内容增高(回答流分页)使其失效(失效条件是 `已滚范围 > 精确值`);
4. 排版偏好变化时清空块高实测缓存重算(字号变了,旧实测值作废)。

代价是首屏尚未滚动时不足以判定可滚动(进度条要等第一次滚动才出现,上游是进入即闪 1.2s),
换取了"进度真实可读、可拖到正确位置"。**已知局限**:问题页正文之后的回答信息流
(`documentItems()`)由页面侧 @Builder 生成,测不到单项高度,该页估算偏小、拇指偏快,
需触底一次校准;回答/文章页(本功能的主要落点)滚动若干屏后估算即接近真实。

组件内部(逐条对应上游 VerticalReadingProgressBar):

1. `maxScrollVp = contentHeightVp − viewportHeightVp`;`<= 1`(无滚动)时不渲染。
2. `thumbHeight = viewport² / contentHeight`,`Math.max(24, …)` 再 clamp ≤ 视口。
3. `progress = scrollYVp / maxScrollVp`(宿主每帧从 `scroller.currentOffset()` 读);
   `thumbY = (viewport − thumbHeight) × progress`。
4. **拖动**:整个 12vp 宽轨道区挂 `PanGesture`:
   `onActionStart` 记起点 progress 并置 `dragging = true`;
   `onActionUpdate` 里 `deltaY / (viewport − thumbHeight)` 累加 progress(clamp 0..1)→
   写入本地 `dragProgress`(拖动期间渲染以它为准,不依赖宿主的 `scrollYVp` 回推时机)→
   `this.scroller.scrollTo({ xOffset: 0, yOffset: progress × maxScrollVp, animation: false })`;
   `onActionEnd`/`onActionCancel` 置 `dragging = false` 并启动淡出计时。
   (ArkUI 无 Compose 的 `startDragImmediately`,PanGesture 的 5vp 起手距离等价。)
5. **淡出**:三个输入 `@Prop` 任一变化都视为"活动中"(显示 + 重置计时,对齐上游
   `showProgressBar`/`isScrollInProgress` 的 LaunchedEffect 语义);最后一次变化后 1200ms 置隐;
   透明度用 `.opacity()` + `animateTo`(出现 120ms / 消失 260ms,
   `Curve.FastOutSlowIn` 与项目现状一致)。
   **隐藏态与命中测试分离(设计稿原方案在真机上不可用)**:设计稿写"alpha=0 且非拖动时
   `if` 分支直接不渲染"(或等价的 `Visibility.None`),实测用 `Visibility.None` 隐藏后,
   再次显示时该节点**仍收不到右缘触摸**——`onTouch` 全程无回调、右缘事件全部落到正文列表,
   轨道区拖动彻底失效(组件实例、`@Prop @Watch`、节点属性都正常,只有命中丢了)。
   落地方案改为:**节点常驻**(视觉靠 `opacity(alpha)`,拖动态与淡出期都只改透明度),
   命中用 `hitTestBehavior(mounted && scrollable() ? Default : None)` 开关;
   `mounted` 是非动画量(不能拿 `alpha` 判定:它在 `animateTo` 起始帧即为 0,
   直接判定会让 260ms 淡出瞬间消失,也会让淡出期失去命中)。
   隐藏态下右缘手势完整交回正文列表(实测中央拖动/右缘拖动都能正常滚动)。
6. **视觉**:轨道区宽 12vp、命中区透明;轨道 2vp 宽
   `$r('app.color.divider_color')`(alpha=0.45)圆角条;
   拇指 4vp 宽 `$r('app.color.brand_primary')`(alpha=0.88)圆角条。深浅色自动跟随资源。
7. 与回答页"上下滑切换回答"手势**需要显式屏蔽**:PanGesture 只在 12vp 轨道区内不抢正文手势,
   但回答页的过滑手势挂在祖先 `parallelGesture` 上、与滚动条拖动**并行识别**,
   故由 `onSeekStateChange` 通知宿主在拖动期间清掉贴边状态(见上)。
8. **拖动可用的前提是进度条当时已可见**(与上游一致):隐藏态下右缘这 12vp 不参与命中,
   触摸直接落到正文列表;要先滚动让进度条浮出,再按住轨道区拖动。

### 5.5 范围外(明确不做 / 二期候选)

- 评论正文、信息流卡片标题的字号联动(上游有,本项目对应渲染点不同,列为二期);
- 行内公式图高度随字号缩放(二期);
- WebView CSS 注入路径(本项目无此渲染路径);
- 详情页底栏排版快捷面板(上游无此交互,不做);
- 滚动条开关设置(上游无,始终渲染)。

## 6. 关键决策记录

1. **行高默认值映射**:上游语义是"line-height / font-size"(默认 160% → 16sp×1.6=25.6sp),
   而本项目现行正文是 16fp/30(比 1.875)。若照搬上游公式,默认视觉会变密(30→25.6),
   全量用户可感回归。**采用归一映射**:`lineHeightVp = 字号 × 1.875 × (行高%/160)`,
   100%/160% 档与现状逐像素一致;滑块范围/步进保持上游不变(100% 档 ≈ 1.17 倍行距,
   作为下限也更合理)。字号、段间距的公式与上游一致,默认值本来就等于现状。
2. **持久化键名直接用上游英文键**(`contentFontSize` 等),与 `answerDoubleTapAction`
   先例一致,便于日后与上游导出/同步对照。
3. **滚动条内容高采用"实测块高估算 + 已滚范围下界 + 触底校准"**,因 SDK 无读最大滚动距离的 API(§4)。
   设计稿原方案(`max(已见滚动量 + 视口)`)会使进度恒为 100%,细节与替代方案见 §5.4。
4. **两个实测风险点**(LazyForEach 刷新、List space 动态性)已按"直改"实现在模拟器上验证通过,
   兜底方案(样式版本号 id / 逐块 margin)未启用,细节见 §5.2。
5. **单位不引入系统字体缩放回归**:`Text.fontSize`/`Text.lineHeight` 传 number 时单位是 fp,
   与旧资源 16fp 同义;`List({ space })` 传 number 时单位是 vp,与旧 `space: 12` 同义。
6. **滚动条必须"窄层 + 常驻节点"**(真机实测得出,细节见 §5.4 第 5/6 条与宿主侧说明):
   - 悬浮层不能用整页 `Row`:实测整页层(无论 `None` 还是 `Transparent`)会进入命中链,
     中央拖动正文列表滚不动;改为宽 12vp 的右对齐子节点,靠 Stack 重叠区域的默认命中规则分流。
   - 节点不能以 `if` / `Visibility.None` 摘出渲染树:摘除后再显示仍收不到右缘触摸,
     拖动彻底失效(实例与 `@Prop @Watch` 都正常,只有命中丢了);改为节点常驻 +
     `hitTestBehavior` 开关,隐藏态 `HitTestMode.None` 把右缘手势完整交回正文。

## 7. 改动文件清单

| 文件 | 改动 |
|---|---|
| `data/src/main/ets/preferences/AppPreferencesStore.ets` | 3 个 key + 默认值/边界常量 + levels/decode/normalize 纯函数 + `loadReaderTypography`/`saveReaderTypography` |
| `data/Index.ets` | **无需改动**(已是 `export *`,新导出自动生效) |
| `entry/src/main/ets/pages/ReaderTypography.ets` | **新增**百分比→像素映射纯函数(宿主与行内公式子组件共用,可单测) |
| `entry/src/main/ets/pages/NativeContentDocument.ets` | `@StorageProp` 三值 + `@Watch`、字号/行高/段间距动态化、块高实测与内容总高估算、挂 ReadingProgressBar |
| `entry/src/main/ets/pages/components/ReadingProgressBar.ets` | **新增**可拖动滚动条组件 |
| `entry/src/main/ets/pages/P1Shell.ets` | 设置页"阅读"卡片(3 个 Slider)+ `restoreReaderTypography`/`applyReaderTypography`/`broadcastReaderTypography` |
| `entry/src/test/ReaderTypography.test.ets` | **新增**9 个用例:档位表、损坏值回退、档位吸附与等距取小、clamp、normalize、默认档映射、缩放 |
| `entry/src/test/List.test.ets` | 注册新用例文件 |

## 8. 验证计划

1. `pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -SkipBuild`
   (编译 + 单测,新用例全过);
2. 完整构建 `-SkipDependencyInstall` → 装 API23 模拟器 `ZhihuPlus_API23`(127.0.0.1:5555);
3. 设置页:`p3_settings` dumpLayout 确认"阅读"卡片与三滑块;调节字号后
   `hilog`/重进设置页确认持久化;
4. 详情页(开一篇文章 + 一个长回答):
   - 默认值截图与改版前对比,**逐像素级确认默认视觉无变化**(字号/行距/段距);
   - 调大字号/段间距后重进详情页,dumpLayout 对比 Text 高度/块间距生效;
   - 详情页开着时回设置页改字号,确认实时联动(或至少重进生效,与实现策略一致);
   - 滚动正文:dumpLayout 确认滚动条出现(`p2_reading_progress_bar` 的 `opacity=1`、
     拇指 `p2_reading_progress_thumb` 位置随进度变化)→ 停 1.2s+ 淡出(`opacity=0`);
     先滚动让进度条浮出、再按住右缘 12vp 轨道区拖动(`uitest uiInput drag 1240 …`),
     确认拇指跟随手指且正文 `scroller` 联动;
   - 隐藏态下中央/右缘拖动都仍能滚动正文(确认没有隐形窄条截走手势);
   - 回答页下滑切换/问题页折叠展开/回答流分页无回归;
5. 深浅色各过一遍(滚动条颜色资源自动适配)。

**本次实测结论**:

- 编译通过;Hypium `590/590` 全过(原 581 + 新增 9),HAP `pack.info` 校验
  target=26 / compatible=23 / bundleName 一致;
- 设置页 `阅读` 卡片三滑块渲染正确(字号滑块值为档位下标 10 == 100%,"行高" 160,"段间距" 100),
  拖动字号滑块后取值即时跟随(实测拖到最右端 → 下标 22 == 200%);
- 默认档位下正文视觉与改造前一致(映射在 100%/160%/100% 上恒等于 16fp / 30 / 12vp,单测断言覆盖);
- LazyForEach 刷新与 `List.space` 动态性均生效,未启用任何兜底方案;
- 滚动条(API 23 模拟器,dumpLayout 读节点属性):
  - 静止态 `opacity=0.000000` / `hitTestBehavior=HitTestMode.None`,不参与命中;
  - 滚动中 `opacity=1.000000` / `HitTestMode.Default`,拇指位置随进度上移
    (实测 `[1221,343]` → `[1221,435]`);
  - 停手 3s 后回到 `opacity=0` / `HitTestMode.None`,拇指停在最后位置;
  - 按住右缘轨道区慢拖(`drag 1240 1000 → 1240 2200`,velocity 300):`onTouch` 收到
    Down/Move/Up 序列,拇指被拖到 `[1221,957]`,正文同步跳到文章深处(`scrollTo` 回写生效);
  - 隐藏态下在右缘起点拖动,手势完整落到正文列表(正文正常滚动,未出现死区)。
