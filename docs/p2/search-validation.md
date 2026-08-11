# P2 搜索纵向切片验证记录

> 基线：DevEco Studio 6.1.1 Release、HarmonyOS 6.1.1（API 24）
> 范围：只读全局搜索；不包含搜索筛选、用户内搜索、热搜、屏蔽规则、端侧 AI 或内容写操作

## Android-master 合同

- `SearchViewModel.kt` 的首请求为 `GET https://www.zhihu.com/api/v4/search_v3`，参数包括
  `gk_version=gz-gaokao`、`t=general`、`q`、`correction=1`、`offset=0`、`limit=20`、
  `search_source=Normal` 和 `show_all_topics=0`。
- include 固定为 `data[*].highlight,object,type`，后续页来自 `paging.next`。
- Android Lite 搜索页面使用 `allowGuestAccess=false`。2026-08-11 对首请求的匿名探测返回 HTTP 400，
  因此 HarmonyOS 搜索不会把匿名失败伪装成游客可用能力：请求必须使用已验证会话 Cookie 和 ZSE96。
- `SearchResult` 只把 `type=search_result` 且 object 为受支持 Feed target 的条目转为内容；`koc_box`、
  `knowledge_ad` 等外壳以及明确未知的 object type 会跳过。HarmonyOS 首批只展示问题、回答和文章。
- Android 的真实响应样本证明 `paging.next` 既可能使用
  `www.zhihu.com/api/v4/search_v3`，也可能使用 `api.zhihu.com/search_v3`。

## HarmonyOS 数据合同

- 首请求由本地 builder 按固定参数顺序生成，关键词先 trim，长度限制为 1–200 个 UTF-16 code unit，
  拒绝控制字符，并采用 Android 一致的空格到 `+` 编码。
- 游标只接受 HTTPS、无 userinfo/端口/fragment/Unicode 控制字符，且必须精确命中上述两个已知
  host/path 组合。游标必须恰好包含一个与当前搜索词相同的 `q` 和一个 `t=general`；跨关键词、重复
  `q/t`、evil-suffix 主机和其他路径均拒绝。
- 两种可信游标来源都只作为参数输入，实际请求统一重建为
  `https://www.zhihu.com/api/v4/search_v3`，并由本地单一常量覆盖 include。Cookie/ZSE 不会发送到
  `api.zhihu.com`。
- 规范化游标键忽略参数顺序、空格编码形式、来源 host/path 和上游 include 差异。已请求游标和指回
  当前/历史页的 next 会安全终止分页；失败请求不提交游标，可用同一游标重试。
- Repository 使用单请求 `ZhihuHttpClient`，页面换词和离页都会取消在途 transport 并增加 generation；
  旧响应不能提交活动关键词、游标或跨页去重集合。
- 搜索项按 `target kind:content id` 去重，不使用可能变化的外层 search wrapper id。不同 target type
  可复用相同数值 ID。
- 解码器区分无效 JSON、结构损坏和知乎 error envelope。明确不支持的外壳或 object type 单项跳过；
  受支持类型缺少 object、ID、标题，或 excerpt/count/paging 字段类型错误时返回结构化错误，不静默吞页。

## 状态与 UI 合同

- `SearchController` 独立管理 idle、首屏 loading、ready、empty、error、加载更多与可恢复分页错误。
- 新关键词先取消旧请求并清空旧结果；首屏失败重试当前关键词，分页失败保留列表并只重试原游标。
- HTTP 认证失败不会与普通网络失败混淆：无状态码或明确 401 才发布固定登录提示，页面通过强类型 Login
  destination 显示“去登录”；403 固定提示“请求被拒绝，可能需要稍后重试或完成风控”，不会误报会话失效。
  返回后保留原关键词和已有结果，用户可直接重试，底层响应和凭据不会进入状态。
- 非终止空页保留 next；空态“重试”继续下一游标。分页错误会锁住自动触底，避免 `onReachEnd` 请求风暴。
- 页面离开取消请求并隔离旧 generation。列表键使用稳定 target identity。
- 页面被内容页、登录页或前后台切换暂时覆盖时保留关键词和已展示列表；若首屏请求恰在离页时被取消，
  重新出现后会开启新 generation 自动重试，不会永久停在 loading。
- 问题、回答和文章分别映射到 `P1DestinationName.QUESTION/ANSWER/ARTICLE`，内部导航不依赖原始 URL。
- 标题和摘要不限制行数，使用现有主题、字体与间距资源；搜索、清除、重试、加载更多和结果项提供稳定 id。
  Safe area 由现有 `P1Shell` 根导航统一处理。
- 错误文案为固定用户文案，不显示响应 body、Cookie、ZSE、原始游标或底层异常。

## 自动化覆盖

搜索测试共 16 个 Hypium 用例：

- `SearchRepository.test.ets` 7 个：首请求/游标生成与规范化、精确来源白名单和跨词拒绝、三类内容解码与
  显式不支持项跳过、结构化 malformed、Cookie/ZSE 与跨页稳定键去重/循环终止、失败后同游标重试、
  取消不依赖 transport settle。
- `SearchState.test.ets` 9 个：空词与 trim、换词取消和旧响应隔离、分页失败重试、非终止空页继续、离页取消及
  返回状态保留、无状态码/401 登录恢复、首屏与分页 403 风控提示、稳定键去重与三类强类型目的地。

## 集成和 API 24 验收清单

1. 在 `data/Index.ets` 导出搜索 models、decoder、repository interface 和默认实现。
2. 在 `entry/src/test/List.test.ets` 注册两个测试 suite；搜索切片现有 16 个用例，全局预期数由主集成步骤按
   同批全部 suite 统一更新，避免并行切片各自写入过时总数。
3. 在 Search 目的地创建 `ZhihuHttpClient`，Cookie provider 使用
   `getAppSessionOwner(context).getRepository()`，再注入 `DefaultSearchRepository`；禁止无 provider 的默认客户端。
4. 由 `P1Shell` 的 Search 分支渲染 `SearchPage`，保留已有返回栈和根 safe area。
5. 运行四模块 API 24 build 和全量 Hypium，再在已登录的 DevEco 虚拟机验证真实首屏、连续分页、换词、
   返回离页、问题/回答/文章导航以及无会话/失效会话的可恢复文案。

共享导出、测试注册、强类型导航和全局会话注入均已完成；API 24 四模块构建与第二批 P2 Hypium
`172/172` 已通过。DevEco 虚拟机已验证搜索页布局；真实搜索仍需有效会话，游客路径会提供固定认证文案与“去登录”动作。
