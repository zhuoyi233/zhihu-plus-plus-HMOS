# P2 知乎日报正文详情验证记录

本切片将日报 API7 的正文映射为既有原生问题、回答或文章详情，不引入 WebView、端侧 AI 或任意外链打开。

- 请求：`GET https://daily.zhihu.com/api/7/story/{storyId}`；story ID 只接受 1–30 位、非零十进制整数。
- 网络：匿名请求、无 Cookie、无 ZSE、禁止重定向，沿用 `ZhihuHttpClient` 的 1 MiB 响应上限与超时策略。
- 解析：仅读取 JSON `body`，优先 `a.originUrl`，其不支持时再读取 `div.view-more a`；只接纳由既有深链解析器识别的文章、问题和回答。
- 跳转：将受信链接转为 `P1Destination`，复用原生详情与阅读记录；用户、视频、任意外站及未解析正文显示“暂不支持原生阅读”。
- 生命周期：重复打开会取消旧请求并丢弃旧结果；页面离开后不再发布导航。

静态用例：`DailyStoryRepository.test.ets` 5 项、`DailyStoryDetailState.test.ets` 5 项。接入 Hypium 清单后总数应由主线复核。

仍需 API24 虚拟机验收：从日报列表点击可映射的真实条目，验证中转页只跳转一次、进入原生内容详情、返回后日报列表仍保留；对外站/视频/无映射日报验证不会离开应用或打开 WebView。
