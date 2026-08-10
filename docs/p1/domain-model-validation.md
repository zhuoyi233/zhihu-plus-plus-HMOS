# P1 DomainModel 与 fixture 验证

## 边界

本阶段依据 Android Lite 的 `Person`、`DataHolder.Question/Answer/Article`、`Feed` 与 `ZhihuPaging` 盘点建立最小领域模型，不包含端侧 AI、评论、通知、写作或推荐算法模型。

- 知乎响应字段只在 `ZhihuDomainDecoder.ets` 的 Wire DTO 中保留 `snake_case`。
- 页面和 Repository 只接触 `camelCase` 的 DomainModel。
- 问题、回答、文章、Feed target 和用户 ID 均保存为 `string`；decoder 会把安全范围内的 JSON 整数 ID 立即转成字符串，并拒绝已经无法精确表示的数字。fixture 中可能超出 JS 安全整数的 ID 直接使用字符串，避免精度丢失。
- 缺失的可选文本和计数归一为 `undefined`、空字符串或 `0`；用户、内容 ID 以及标题等可导航必需字段缺失时抛出分类后的 `DomainDecodeError`。
- Feed P1 只接收只读 MVP 首批目标：问题、回答和文章；其他类型明确返回 `UNSUPPORTED_CONTENT`，不会静默伪装成已支持内容。

## Repository 契约

Repository 只定义存在业务语义的异步能力：

- `FeedRepository.loadHomePage`：加载首页及其游标。
- `ContentRepository`：按字符串 ID 获取问题、回答或文章详情。
- `PeopleRepository.getUser`：按用户 ID 或 URL token 获取用户。

本阶段不提供仅转发 HTTP 调用的实现类。数据源选择、缓存和会话失效策略在具体 Repository 落地时实现，避免预先制造无行为的包装层。

## 脱敏 fixtures

`entry/src/main/resources/rawfile/fixtures/` 固化以下可复现输入：

| 文件 | 覆盖 |
| --- | --- |
| `user.json` | 用户、关注状态、组织标记与 `snake_case` 字段 |
| `question.json` | 长字符串问题 ID、计数、时间和嵌套作者 |
| `answer.json` | 字符串回答 ID、关联问题 ID、正文和作者 |
| `article.json` | 长字符串文章 ID、正文、计数和组织作者 |
| `feed-page.json` | 回答/文章 Feed item 与非末页游标 |
| `empty-fields.json` | 空列表、空下一页地址和末页游标 |
| `error-response.json` | 脱敏的知乎错误 envelope；确认错误响应不会被当作业务数据 |

fixture 不包含 Cookie、真实用户标识或真实正文。后续 Android/HarmonyOS golden 对比应直接读取这些 rawfile，并对 DomainModel 输出排序后的规范化 JSON。

## 自动化验证

`DomainModel.test.ets` 覆盖：

1. `snake_case` 到 `camelCase` 的边界映射。
2. 数字及字符串 ID 都输出为字符串。
3. 用户、问题、回答、文章和 Feed item 的最小字段。
4. `is_end/is_start/next/previous/page/totals` 分页游标。
5. 空列表、缺失可选字段、无效 JSON、缺失必需字段及不支持的 Feed 类型。

该测试文件由 P1 测试框架汇总入口注册；本并行任务按文件边界不修改 `List.test.ets`。
