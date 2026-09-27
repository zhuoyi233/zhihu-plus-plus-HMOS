# 多层级父子页面保活实现笔记——以评论页为例

> 总结日期：2026-09-27<br>
> 案例基线：`feature/child-comment-scroll-restore` `a7c69194`（修复"从子评论页返回后根评论列表回顶"，
> 经历两轮方案：位置保存/重放 → 结构保活）<br>
> 上游参考：zly2006/zhihu-plus-plus `shared/.../ui/CommentScreen.kt`、
> `shared/.../ui/components/CommentScreenComponent.kt`（refs/remotes/upstream/master）<br>
> 范围：提炼评论页"根评论列表 ↔ 子评论页"多层父子页面在鸿蒙 ArkTS/ArkUI 端的实现经验与通用规则，
> 适用于其他需要"进入下一层、返回后原层原样保留"的页面（如详情页内的二级列表、嵌套筛选面板等）。

## 一、问题与背景

评论页存在两层列表：根评论列表（`p3_comments_root_list`）与子评论页（点"查看 N 条子评论"进入，
`p3_comments_children_list`，含置顶的根评论卡片）。原始实现是**同一个页面组件内用 `if/else`
按 `activeRoot` 状态在两份 `List` 间切换**，两个列表共用一份 `items` 数据（控制器快照只携带
"当前层"的数据）。

由此产生 bug：进入子评论页时根 `List` 被销毁，返回时重建，滚动位置归零。修复过程走了两轮方案，
第二轮才彻底解决，两轮的经验都有沉淀价值。

## 二、上游安卓实现剖析

上游（Compose）的做法有两个层面，缺一不可：

1. **结构保活（主要手段）**：`CommentScreenComponent` 承载**两个叠加的 `ModalBottomSheet`**——
   根评论弹层与子评论弹层。点开子评论时第二层弹层盖在第一层上，根评论的 `CommentScreen`
   **始终保持组合，从不销毁**。两个列表的数据来自独立的 ViewModel（`RootCommentViewModel` /
   `ChildCommentViewModel`），天然不共用电位。

2. **位置重放（兜底手段）**：根列表的 `LazyListState` 由外层以
   `rememberSaveable(saver = LazyListState.Saver)` 提升保存；`CommentScreen` 内部另有
   `restoredListPosition`（记录 `firstVisibleItemIndex + scrollOffset`），在 ViewModel 异步重建、
   数据到位后（`LaunchedEffect(viewModel.allData.size)` 等到列表非空）显式 `scrollToItem` 重放。
   注释明确说明这是防"恢复的 LazyListState 被异步重建压回顶部"。子评论层则"不进行状态保存"，
   关闭时通过 `childListResetToken += 1` 有意重置。

即：**结构保活为主，位置重放只兜"真重建"场景**（进程恢复、异步重建）。这为鸿蒙端的方案
取舍提供了直接依据。

## 三、鸿蒙端方案演进与教训

### v0：if/else 切换（原始实现）

`sheetBody()` 里 `if (activeRoot !== undefined)` 切换两份 `List`。 ArkUI 中 **if/else 分支切换 =
组件销毁重建**：滚动位置、已解码的 Image、子树状态全部丢失。共用的 `this.items`（只有当前层
数据）也使"两列表同时存活"在数据上不可能。

### v1：位置保存/重放（治标）

第一轮修复在 UI 层补了与上游类似的"位置重放"：进入子评论前捕获
`rootScroller.currentOffset().yOffset`（`applyState` 状态切换处，所有打开入口的必经点），
返回后在根列表重建完成的首次布局回调（`onAreaChange` 首次挂载必触发）里 `scrollTo` 重放。

实测位置保住了，但**返回瞬间闪屏、头像短暂消失**——根列表仍是重建的：全部评论行都是新节点，
头像 Image 重新解码（短暂空白），列表先按顶部渲染再跳到原位。结论：

> **位置重放救不回节点重建的视觉损失。只要组件被销毁，"先见顶部再跳转 + 图片重载"就无法避免。**
> 位置保存/重放只应作为真重建场景（进程恢复、异步数据重建）的兜底，不能替代结构保活。

### v2：结构保活（治本，最终方案）

对齐上游双弹层叠加的结构语义：

- 两份 `List` 常驻同一个 `Stack`，进入子评论层时根列表仅 `.visibility(Visibility.None)`——
  组件树保持挂载，滚动位置、已解码头像、布局原生保留，返回即"重新显示"，没有任何重建帧；
- 子评论层按状态叠加：`LOADING`/`ERROR` 显示占位面板，其余显示子评论列表（空态用
  `暂无回复` ListItem）；
- **数据源拆分**（保活的必要前提，见下节）：`CommentViewState` 新增 `rootItems`（始终携带根层
  数据），UI 持 `rootListItems` / `childListItems` 两个 @State 数组分别绑定两个列表；
- 原 v1 的 save/restore 代码全部移除。

## 四、关键规则提炼

### 1. 保活 vs 重建的判定口径

| 场景 | 正确做法 | 原因 |
| --- | --- | --- |
| 层级前进/后退（子评论、二级面板） | Stack + `Visibility.None` 保活 | 用户预期"返回后原样"，重建必闪屏 |
| 有意重载（切排序、重试、刷新） | 维持销毁重建、回顶部 | 本来就是重新开始，保活反而错位 |
| 进程恢复/异步重建 | 保活 + 位置重放兜底 | 上游 `restoredListPosition` 的适用场景 |

注意：保活的根列表在"有意重载"时仍会经状态面板分支卸载（根层 `LOADING`/`ERROR`/`EMPTY`
走 `statusPanel`），这是有意保留的语义，不要"顺手"也保活。

### 2. 保活的前提是数据源拆分，而快照设计是根源

原始 bug 的深层原因在控制器快照：`CommentViewState.items` 只携带"当前层"的数据。两个列表若
共用一份 `items`，隐藏的根列表会跟随子评论数据错误重渲染（key 全变 → 行重建，等于没保活）。
因此：

- 控制器/状态机快照应**为每个存活层各携带一份数据**（`items` = 当前层，`rootItems` = 常驻层），
  而不是只给"当前层"聚合值；
- UI 侧每个保活列表绑定自己独立的 @State 数组；
- `items` 的旧语义（当前层）保留不变，已有测试断言全部不受影响——扩展快照字段比改语义便宜得多。

### 3. 跨层可变状态用"合并语义的共享 store"同步

点赞状态走 `CommentLikeStateStore`（Map 累积、`sync` 为合并语义，可多来源多次 sync），
配合快照始终携带 `rootItems`，子评论层内点赞可实时同步到隐藏的根列表（含评论内子评论预览行），
返回后无旧值。这与上游 `updateCommentLikes` "同步根列表、内嵌回复与回复页"的意图一致。
行节点因此得以复用——store 的类注释"更新时保留评论行和头像节点"就是这个设计意图。

### 4. ArkTS/ArkUI 具体坑

- **`Scroller` 不跨重建恢复位置**：列表销毁重建后即使复用同一 Scroller 实例，新列表仍从 0 开始；
  不要指望 Scroller 隐式恢复。
- **`Visibility.None` 才是保活**：不占布局空间但组件存活，是"隐藏保活"的正确原语；
  `if/else` 是销毁，二者语义完全不同。
- **`onAreaChange` 首次挂载必触发**：可作为"新列表完成首次布局"的信号（v1 重放时机的依据）；
  本仓 `NativeContentDocument` 也依赖此特性做初始测量。
- **@Builder 内 optional 收窄不跨方法**：`this.pinnedRootCard(this.activeRoot)` 传入
  `CommentItem | undefined` 会类型报错，需在目标 @Builder 体内重新 `if (this.activeRoot !== undefined)`
  守卫后再使用（同一 builder 体内的 if 守卫 + 闭包内使用是既有可编译模式）；不要在
  @Builder 体内用 `const` 局部变量中转（@Builder 体内禁止非 UI 语句）。
- **列表放入 Stack 后尺寸要显式化**：原 `layoutWeight(1)`（Column 语义）改为
  `.width('100%').height('100%')`，`layoutWeight` 移到 Stack 本身。

### 5. 顶栏/底栏沉浸布局的兼容

保活改造不改变列表的 `contentStartOffset(FLOATING_TITLE_BAR_OFFSET)` /
`contentEndOffset(bottomChromeHeight() + 16)` 机制，隐藏期间这些属性随键盘等状态更新无副作用。
返回后首屏让位与滚动位置在同一坐标系（`currentOffset` 的保存/恢复/自然保留三者对称）。

## 五、验证方法论

本次 E2E 验证在 API 23 模拟器（127.0.0.1:5555）完成，可复用的手段：

1. **先复现再验证**：先在旧包上走完整操作序列（进入 → 滚动两屏 → 记录可见评论集合 →
   进子评论 → 返回 → 对比），确认 bug 存在且用例有效，再装新包走同一序列。
2. **零重建的客观证据——dumpLayout 节点 `hashcode` 对比**：返回前后各 dump 一次，对相同
   `id` 的节点（列表本体、头像、正文等）比对 `attributes.hashcode`。保活方案实测
   `same=9 changed=0 gone=0 added=0`；若走了重建，hashcode 全新。这是"无闪屏"最硬的
   证据，比截图捕捉中间帧可靠。
3. **位置保持的证据**：对比返回前后可见的评论作者集合（`p3_comments_author_*`）是否一致。
4. **保活不破坏滚动**：返回后继续上滑/下滑各一屏，确认能正常浏览且滚回顶部后排序条等
   首屏元素正常。
5. **状态机语义回归靠单测**：控制器测试 `opensAndClosesChildCommentsPreservingRootList`
   补充 `rootItems` 在子评论层打开期间仍携带根数据的断言；Hypium 全量 664/664。

## 六、涉及文件

- `entry/src/main/ets/pages/CommentLayer.ets`：评论页 UI（Stack 双列表保活、双层状态面板、
  数据源拆分绑定）；
- `entry/src/main/ets/pages/CommentState.ets`：`CommentViewState.rootItems` 与快照输出；
- `entry/src/main/ets/pages/CommentLikeState.ets`：合并语义的点赞状态 store（既有设施）；
- 上游参考：`ui/CommentScreen.kt`（restoredListPosition 重放）、
  `ui/components/CommentScreenComponent.kt`（双弹层叠加 + rememberSaveable 列表状态）。
