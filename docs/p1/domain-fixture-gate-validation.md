# P1 Domain fixture 设备门禁验证

## 目的与边界

主机 Hypium 测试只验证 fixture catalog 的静态合同，不声称能读取 HAP 中的 rawfile。真实资源门禁必须安装到 API 24 设备，由 `ResourceManager.getRawFileContent()` 读取 `entry/src/main/resources/rawfile/fixtures/` 下的 7 个 JSON，并交给 `data` 模块现有 decoder。

门禁不包含 Cookie、网络请求或端侧 AI。失败摘要只显示 fixture 文件名与受控错误类别，不记录 decoder 原始异常文案，也不回显 JSON payload。

## 固定合同

| rawfile | decoder | 预期 |
| --- | --- | --- |
| `fixtures/user.json` | `decodeUser` | 成功，用户字段与 snake_case 映射成立 |
| `fixtures/question.json` | `decodeQuestion` | 成功，长字符串 ID、计数与作者成立 |
| `fixtures/answer.json` | `decodeAnswer` | 成功，回答与问题字符串 ID 成立 |
| `fixtures/article.json` | `decodeArticle` | 成功，文章计数与组织作者成立 |
| `fixtures/feed-page.json` | `decodeFeedPage` | 成功，2 条内容与非末页游标成立 |
| `fixtures/empty-fields.json` | `decodeFeedPage` | 成功，空列表与末页游标成立 |
| `fixtures/error-response.json` | `decodeFeedPage` | 按预期抛出 `UPSTREAM_ERROR` |

## API 24 设备验证

1. 使用 DevEco Studio 6.1.1 Release / HarmonyOS API 24 构建并安装 `entry`。
2. 从“技术实验室”进入“Domain fixture 设备门禁”。页面进入后会自动运行；也可点击“重新运行”。
3. 等待 `p1_domain_fixture_gate_status` 显示 `通过：8/8`。
4. 点击 `p1_run_domain_fixture_gate` 再运行一次，确认仍为 `通过：8/8`，且不存在 `p1_domain_fixture_gate_failures`。
5. 使用 `p1_domain_fixture_gate_back` 返回，确认 Navigation 返回栈正常。

设备证据应记录：模拟器名称、API 版本、HAP 构建提交、门禁状态文本，以及必要的页面截图。若显示失败，只能在设备日志和 UI 中保留文件名及 `resource_read_failed`、`decoder_rejected`、`expected_failure_missing`、`wrong_failure_kind` 或 `contract_mismatch` 等安全类别。

## 主机测试范围

`DomainFixtureGate.test.ets` 提供 3 个纯测试：

1. catalog 恰好包含 7 个唯一 rawfile 文件名；
2. 8 份 fixture 各自绑定唯一的 decoder 合同类型；
3. 仅错误 envelope 预期失败，且分类必须为 `UPSTREAM_ERROR`。

这些测试不会复制 fixture JSON，也不把“catalog 正确”表述为“设备已读取 rawfile”。

## 实测结果

DevEco 虚拟机 `ZhihuPlus_API24`（HarmonyOS 6.1.1 / API 24）进入该目的地后，`p1_domain_fixture_gate_status` 实际显示 `通过：8/8`。该结果来自打包 HAP 的 `ResourceManager.getRawFileContent()`，不是主机内嵌 JSON 或 catalog 数量推断；页面未生成失败列表。
