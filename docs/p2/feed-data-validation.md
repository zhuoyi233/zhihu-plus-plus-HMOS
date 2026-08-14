# P2 首页 Feed 数据链路验证

## 范围

本阶段只建立 Android Lite 对标的只读首页 Feed 数据链路，不包含登录、互动、端侧 AI、WebView 正文或其他发现页。

## Android-master 证据

- `shared/src/commonMain/kotlin/com/github/zly2006/zhihu/viewmodel/feed/HomeFeedViewModel.kt`：历史 `initialUrl` 为 `https://api.zhihu.com/topstory/recommend`，并显式允许游客访问。
- `shared/src/commonMain/kotlin/com/github/zly2006/zhihu/viewmodel/PaginationViewModel.kt`：请求追加 `include=data[*].content,excerpt,headline,target.author.badge_v2`，后续页使用响应的 `paging.next`。
- `app/src/androidTest/java/com/github/zly2006/zhihu/test/ZhihuMockApi.kt`：Mock 首页端点为 `https://api.zhihu.com/topstory/recommend`，响应沿用 `data` 与 `paging` 信封。
- Android 分页实现跳过不能识别的单项，而不是让整页失败。HarmonyOS 同步跳过 Android 已列明的 `invited_answer`、`tab_list`、`feed_item_index_group` 外壳和不支持的 target；其他缺少 ID、标题或 target 等结构损坏仍返回结构化解码错误。

## HarmonyOS 合同

- 当前知乎已对历史游客端点返回 HTTP 403，因此首页切换为已登录网页接口：
  `https://www.zhihu.com/api/v3/feed/topstory/recommend?desktop=true&page_number=1&limit=10&action=down`，附加统一 `include`。
- 后续游标只接受 HTTPS、精确主机 `www.zhihu.com`、精确路径 `/api/v3/feed/topstory/recommend`；拒绝用户信息、端口、片段、Unicode/控制字符、其他路径和 evil-suffix 主机。
- 每次请求都由本地 URL builder 覆盖 `include`，不信任上游游标携带的旧值。
- 首页请求使用已验证的 Cookie 与 ZSE。HTTP 主机能力继续限制 `api.zhihu.com` 只能发送游客无签名请求；会话仅能发送到精确 `www.zhihu.com`，拒绝发生在读取 Cookie provider 之前。
- HTTP 状态、传输异常和解码异常沿用 P1 结构化失败；错误消息不包含响应 body 或被拒绝的游标。
- Repository 仅在成功解码并验证下一游标后记录当前游标，网络失败允许原游标重试。
- Repository 的 `cancel()` 会开启新 generation 并终止 HTTP；页面离开会调用该入口，旧响应不能写回分页状态。Controller 同时禁止加载中刷新，避免同一个单请求客户端进入 BUSY。页间条目按 `target.kind:target.id` 去重，与 Android Lite 的稳定展示键一致。
- 已请求游标按规范化后的实际请求 URL 记账，参数顺序、编码形式和被本地覆盖的旧 `include` 不会绕过循环检测。若上游返回已请求过的下一游标，则保留本页新内容并安全终止分页。
- 过滤后空页合法；是否结束以可信 `paging.is_end` 为准。非终止空页保留下一游标，空态“重试”会继续该游标，而不是重新刷新首屏。

## 自动化用例

`entry/src/test/HomeFeedRepository.test.ets` 包含 7 个 Hypium 用例：

1. 首次与分页 URL 的精确生成、旧 include 替换；
2. 精确 HTTPS host/path 游标边界与 evil-suffix 拒绝；
3. 游客请求不读取 Cookie、不发送 Cookie/ZSE；
4. 按 target 稳定键跨页去重，并允许不同类型复用数值 ID；
5. 临时 HTTP 失败后同游标可重试，响应正文不泄漏；
6. 拒绝响应中的恶意游标且不泄漏其内容；
7. 取消不依赖底层 transport settle，旧响应不能污染新 generation。

现有网络测试同时覆盖 `api.zhihu.com` 精确主机允许与 evil-suffix 拒绝；领域测试覆盖混合页跳过不支持 target，并保留受支持内容。`feed-page-mixed.json` 已注册到设备 fixture gate，随其他 rawfile 一起验证实际打包与解码合同。

## 集成结果

`data/Index.ets` 已导出 `DefaultFeedRepository`，`homeFeedRepositoryTest()` 已注册到 `entry/src/test/List.test.ets`。生产首页使用该 Repository 读取真实游客 Feed；最终四模块 API 24 构建和 Hypium `128/128` 通过，`ZhihuPlus_API24` 已验证冷启动、刷新和连续滚动分页。
