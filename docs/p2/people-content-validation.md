# P2 用户主页内容列表验证

本切片补齐用户主页的只读回答、文章和动态列表；不包含关注、点赞、评论、分享、发布或端侧 AI。

| 分区 | 端点 | 允许展示的目标 | 打开目标 |
| --- | --- | --- | --- |
| 回答 | `/api/v4/members/{identifier}/answers` | 回答 | `Answer` |
| 文章 | `/api/v4/members/{identifier}/articles` | 文章 | `Article` |
| 动态 | `/api/v3/moments/{identifier}/activities` | 回答、文章、想法 | `Answer`、`Article`、`Pin` |

- 标识沿用 People 详情的 1–200 位 ASCII 门禁；首次请求和分页均使用已验证标识。
- 所有请求只向 `www.zhihu.com` 发起，因此仅在已有登录会话时携带 Cookie 与 ZSE 签名；不会将凭据发送到 `api.zhihu.com` 或外部游标。
- 分页地址必须精确匹配当前标识、当前分区的 HTTPS endpoint，长度上限为 4096；请求过的游标与重复内容均被去重，循环游标会结束分页。
- 切换分区和离开用户页都会取消前一请求；迟到结果不能回写已销毁页面。401 显示登录入口，403 仅显示可重试的风控提示。
- `p2_people_content_tabs`、`p2_people_content_list`、`p2_people_content_{kind}_{id}`、加载更多和错误按钮提供 API24 UI 验收定位点。

静态 Hypium 覆盖固定 endpoint、外部游标拒绝、会话签名、解码、跨页去重、分页状态和离页取消。仍需使用真实登录会话在 DevEco API24 虚拟机验证三个端点的实际可用性、滚动分页与目标详情跳转。
