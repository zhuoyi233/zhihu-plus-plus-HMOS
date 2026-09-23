# 鸿蒙「双胶囊」悬浮底栏实现方案（酷安式）

> 本文整理自一次关于酷安鸿蒙版底部双胶囊导航的讨论笔记。
> 文中所有 API 版本与签名均已对照本机 SDK 声明文件核对（DevEco Studio
> `sdk/default/openharmony/ets/api`），并**修正了原笔记中若干不准确的说法**（详见 §5、§6）。

---

## 1. 结论速览

| 问题 | 结论 |
| --- | --- |
| 酷安这个底栏是原生组件吗 | **不是**。是完全自定义布局：`Stack` 浮层 + 两个互相独立的圆角容器 |
| 能用原生 `Tabs` / `Navigation` 做吗 | **不能**。原生 `tabBar` / `toolbar` 是一整根通栏容器，无法在中间断开成两个独立材质容器 |
| 沉浸光感怎么来的 | 系统级材质 `systemMaterial(uiMaterial.ImmersiveMaterial)`，**不是**普通 `backdropBlur` / `backgroundBlurStyle` 毛玻璃 |
| 为什么看起来是"两个胶囊" | 两个 `Row` 各自一套圆角 + 各自一套材质，`justifyContent(FlexAlign.SpaceBetween)` 推到左右两端，中间自然断开 |
| 会挡住底部手势条吗 | 必须手动避让：窗口全屏 + `expandSafeArea` 让正文延伸到底，浮层再按手势条高度加 `padding` |
| 能不能在本项目直接用 | **当前不能**（见 §7）：`uiMaterial` 是 API 26 专属，本项目最低兼容 API 23，禁止 import |

---

## 2. 为什么必须放弃原生 tabBar

- `Tabs` 的 `tabBar`、`Navigation` 的 `toolbar` 在布局上都是**单一连续容器**：一整条横条，背景/材质/圆角挂在同一个容器上。
- 想要"左右两个各自带材质的胶囊、中间断开"，本质是**两个平级容器**，原生结构里没有这个插槽。
- 所以正确路线是：页面主体在下、`Stack` 叠一层自定义浮层在上，底栏**完全手写**。

---

## 3. 实现骨架（四层，从下往上）

```text
┌ 窗口全屏 setWindowLayoutFullScreen(true) ─────────────┐
│  ① 正文 Scroll  .expandSafeArea(BOTTOM)  ← 画到手势条下面 │
│  ② Stack 上层浮层：Row(SpaceBetween) 左胶囊 / 右胶囊      │
│  ③ 浮层底部 padding = 手势条安全区高度（避让）            │
│  ④ 系统手势条（Navigation Indicator）                    │
└──────────────────────────────────────────────────────┘
```

### ① 窗口开启沉浸式

```ts
// EntryAbility：内容延伸到底部安全区（本项目已实现）
mainWindow.setWindowLayoutFullScreen(true)
```

### ② 正文延伸到手势条之下

```ts
Scroll(this.scroller) {
  Column() { /* 正文内容 */ }
}
.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
```

> `expandSafeArea` 的意义：正文画面真的画到手势条下面，上层材质才有"背景内容"可折射/模糊，
> 否则底下是纯背景色，光感效果出不来。

### ③ 上层浮层：两个独立胶囊（核心）

```ts
Stack({ alignContent: Alignment.Bottom }) {
  // 下层：正文
  Scroll(this.scroller) { /* ... */ }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .onDidScroll((scrollOffset: number) => this.onContentScroll(scrollOffset))

  // 上层：自定义双胶囊底栏
  Row() {
    Row() {                       // 左胶囊：写评论
      Image($r('app.media.ic_comment')).width(20).height(20)
      Text('写评论').fontSize(13).margin({ left: 4 })
    }
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .borderRadius(99)             // 胶囊圆角
    .backgroundColor('#59FFFFFF') // 材质不可用时的兜底半透明底
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN) // 兜底毛玻璃
    // ✅ 系统级沉浸光感材质（API 26 起，见 §7）
    // .systemMaterial(new uiMaterial.ImmersiveMaterial({
    //   style: uiMaterial.ImmersiveStyle.ULTRA_THIN
    // }))
    .onClick(() => { /* 打开评论输入 */ })

    Row() {                       // 右胶囊：点赞 / 收藏 / 转发
      Image($r('app.media.ic_like')).width(20).height(20).onClick(() => {})
      Image($r('app.media.ic_star')).width(20).height(20).margin({ left: 16 }).onClick(() => {})
      Image($r('app.media.ic_share')).width(20).height(20).margin({ left: 16 }).onClick(() => {})
    }
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .borderRadius(99)
    .backgroundColor('#59FFFFFF')
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
  }
  .width('100%')
  .justifyContent(FlexAlign.SpaceBetween)          // 左右分开，中间断开
  .padding({ left: 16, right: 16, bottom: this.bottomSafeVp })
  .hitTestBehavior(HitTestMode.Transparent)        // 胶囊之间空白区点击穿透到正文
  .translate({ y: this.barOffsetY })               // 滚动显隐
  .opacity(this.barOpacity)
  .animation({ duration: 200, curve: Curve.EaseOut })
}
```

关键点：

- **两个 `Row` 互相独立**：各自圆角、各自材质，视觉上就是两个分开的胶囊。
- **容器设 `hitTestBehavior(Transparent)`**：否则撑满整行的浮层会吃掉正文的点击/滑动。
- **图标 + 文字 + 各自 `onClick`**：图里那一排（写评论 / 点赞 / 收藏 / 转发）就是胶囊内嵌套控件，没有别的玄机。

### ④ 底部避让系统手势条

```ts
// 手势条安全区高度（vp）
const area = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
const bottomVp = px2vp(area.bottomRect.height)
```

> 本项目已有基建：`EntryAbility` 已把 `area.bottomRect.height / density` 写入 AppStorage
> 键 `bottomRectHeight`，页面用 `@StorageProp('bottomRectHeight')` 直接取即可，无需重复计算。

---

## 4. 关键 API 速查表（版本已核对）

| API | 作用 | 起始版本 | 备注 |
| --- | --- | --- | --- |
| `window.Window.setWindowLayoutFullScreen(true)` | 窗口全屏，内容延伸到安全区 | 早期版本 | 沉浸式的前置条件 |
| `.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])` | 组件绘制区扩展到系统安全区 | API 12 | 让正文画到手势条之下 |
| `.systemMaterial(material)` | 通用属性：给组件挂系统材质 | API 26 | 参数类型 `SystemUiMaterial \| undefined` |
| `uiMaterial.ImmersiveMaterial` | 沉浸光感材质（动态折射/透光/流光） | **API 26 / 26.0.0** | 不是普通模糊 |
| `uiMaterial.ImmersiveStyle` | `ULTRA_THIN / THIN / REGULAR / THICK / ULTRA_THICK` | API 26 | 默认 `REGULAR` |
| `ImmersiveOptions` | `style`、`materialColor`、`colorInvert`、`applyShadow`、`interactive`、`lightEffect` | API 26 | `materialColor` 必须带透明度，否则会完全挡住材质 |
| `uiMaterial.isImmersiveMaterialSupported()` | 判断**当前设备**是否支持沉浸材质 | API 26 | 源码注释明确：返回 false 时设置不生效 |
| `uiMaterial.getGlobalMaterialLevel()` | 设备算力档位 `EXQUISITE/GENTLE/SMOOTH` | API 26 | 低算力（`SMOOTH`）上部分视觉参数不生效 |
| `.backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)` | 普通毛玻璃兜底 | 低版本可用 | 无动态折射，观感弱于沉浸材质 |
| `getWindowAvoidArea(TYPE_NAVIGATION_INDICATOR)` | 取底部手势条避让高度 | 早期版本 | 单位 px，需 `px2vp` |
| `UIContext.bindTabsToScrollable(tabsController, scroller)` | **`Tabs` 与可滚动容器联动** | API 13 | ⚠️ 不是滚动偏移监听器，见 §5 |

---

## 5. 滚动联动：原笔记的说法需要更正

原笔记写"用 `bindTabsToScrollable` 监听 Scroll 偏移量"——**这是错的**。SDK 里的真实签名是：

```ts
// @ohos.arkui.UIContext.d.ts:5442  @since 13
bindTabsToScrollable(tabsController: TabsController, scroller: Scroller): void;
```

它用于把 `Tabs` 与一个可滚动容器（如 `Scroll`）**绑定联动**（滚动容器与 Tabs 的嵌套/同步行为），
既不是偏移量回调，也和"底栏跟随滚动隐藏"无关；而且它要求存在 `TabsController`，自定义浮层根本没有 Tabs。

**正确做法**：用 Scroll 自己的滚动回调判方向，驱动位移动画。

```ts
@State barOffsetY: number = 0
@State barOpacity: number = 1
private accumulatedOffset: number = 0

private onContentScroll(delta: number): void {
  this.accumulatedOffset += delta
  if (this.accumulatedOffset <= 0) {          // 到顶：强制显示
    this.barOffsetY = 0; this.barOpacity = 1; return
  }
  if (Math.abs(delta) < 4) { return }         // 迟滞阈值，避免抖动
  // delta > 0：内容上移（手指上滑）→ 隐藏；delta < 0：下滑 → 显示
  const hide: boolean = delta > 0
  this.barOffsetY = hide ? 96 : 0
  this.barOpacity = hide ? 0 : 1
}
```

补充建议：

- 隐藏位移量建议 ≥ 胶囊高度 + 底部 padding，避免残留一条边露出来。
- 用 `onDidScroll` 的**增量**判方向最直观；若用绝对偏移需自行维护上一次值（同本项目
  `onScrollOffset` 的既有套路，并注意切换内容后残余回调的竞态守卫）。
- 动画统一挂在容器上（`.animation`），不要在回调里手写逐帧。

---

## 6. 踩坑清单（含原笔记勘误）

| 原说法 | 更正 / 补充 |
| --- | --- |
| 用 Navigation 自带 toolbar 也行 | ❌ 原生 toolbar 是连续通栏，无法切成两个独立材质容器，只能手写 |
| 普通 `.backdropBlur` 一样 | ❌ 普通模糊没有动态透光折射，观感与系统质感不同；真要同款只能用 `ImmersiveMaterial`（或 HDS 组件自带材质） |
| `ImmersiveMaterial` 需要 API 18+ | ⚠️ **不准确**：本机 SDK 声明为 `@since 26.0.0`（API 26）。且即便 SDK 版本够，还要用 `isImmersiveMaterialSupported()` 判断**设备**是否支持；设备算力档位低时部分参数还会失效 |
| 胶囊必须放在安全区上方 | ✅ 正确。还要区分：`expandSafeArea` 是让**正文**延伸下去，浮层则是**额外加 padding** 抬起来，两者方向相反，别写反 |
| —— | ➕ 浮层容器记得设 `hitTestBehavior(Transparent)`，否则整条浮层挡住正文滚动与点击 |
| —— | ➕ `ImmersiveMaterial` 的 `materialColor` 不能是不透明纯色，否则材质效果被完全遮住 |
| —— | ➕ API 26 的 `systemMaterial` 优先级高于 `backgroundColor`/`blur`/`shadow`/`border`，两者同时设置时以材质为准；不想用材质要显式传 `uiMaterial.Material.empty` |

---

## 7. 落到本项目（zhihu-plus-plus-HMOS）的约束

1. **`uiMaterial` 在本项目禁止 import**：项目最低兼容 API 23（HarmonyOS 6.1.0），而
   `@ohos.arkui.uiMaterial` 全家族是 API 26 专属，**低版本设备载入即崩**。
   → 现阶段做同款双胶囊只能用兜底方案：`backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)`
   + 半透明底色 + 细边框；系统级材质只能走 HDS 组件（自 6.1.0(23) 起可用）。
2. **已有可复用基建**（不要重复造）：
   - `EntryAbility`：`setWindowLayoutFullScreen(true)`，并把底部避让高度写入
     AppStorage 键 `bottomRectHeight`（`px / density`，已是 vp）。
   - `P1Shell` 第 956 行已用 `.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])`。
3. **若将来要引入沉浸材质**：必须在运行期做能力判断 + 代码隔离（不能静态 import 到公共模块），
   并保持低版本降级路径可编译可运行。

---

## 8. 与官方悬浮 BottomTab 的区别

| | 官方悬浮 BottomTab | 酷安式双胶囊 |
| --- | --- | --- |
| 容器数量 | 1 个连续圆角矩形（通栏胶囊） | 2 个独立圆角胶囊，中间断开 |
| 来源 | 官方标准组件能力 | 应用完全自定义布局（Stack 浮层 + Row） |
| 材质 | 系统材质（组件自带） | 需自己给每个胶囊挂材质 |
| 避让安全区 | 组件内部处理 | 应用自己算 `bottomRectHeight` |

---

## 9. 核对记录

- `sdk/default/openharmony/ets/api/@ohos.arkui.uiMaterial.d.ts`：模块级 `@since 26.0.0`；
  `enum ImmersiveStyle`（L174，`ULTRA_THIN=0 … ULTRA_THICK=4`）；
  `function isImmersiveMaterialSupported(): boolean`（L296）；
  `function getGlobalMaterialLevel(): MaterialLevel`（L280）；
  `class ImmersiveMaterial extends Material`（L503）；
  属性签名 `systemMaterial(material: SystemUiMaterial | undefined)`（L284 注释引用）。
- `sdk/default/openharmony/ets/api/@ohos.arkui.UIContext.d.ts:5442`：
  `bindTabsToScrollable(tabsController: TabsController, scroller: Scroller): void`，`@since 13`。
- 本项目：`entry/src/main/ets/entryability/EntryAbility.ets:168`（全屏）、`:225`（`bottomRectHeight`）；
  `entry/src/main/ets/pages/P1Shell.ets:956`（`expandSafeArea`）。
