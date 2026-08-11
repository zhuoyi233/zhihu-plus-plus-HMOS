# P1/P2 Hypium 测试注册

## 注册范围

`entry/src/test/List.test.ets` 保留全部既有导入和调用的相对顺序，并按“启动编排 → 领域模型与 fixture → HTTP → 持久化 → 导航 → P2 Feed/会话”的语义顺序注册测试入口。

1. `domainFixtureGateTest()`：校验打包后的领域 fixture 清单、加载和解码门禁。
2. `zhihuHttpClientTest()`：校验共享 HTTP 会话、请求生命周期和结构化错误。
3. `p1PersistenceTest()`：校验 Preferences 与 RDB 持久化契约。

P2 新增的 Feed Repository、Feed 状态、会话仓库和二维码协议入口同样只导入、调用一次；原有入口的相对顺序未改变。

## 源码静态计数

以下数量由各测试文件中行首 `it(` 调用静态计算得出，不沿用历史测试总数：

| 执行顺序 | 测试组 | `it()` 数 |
| ---: | --- | ---: |
| 1 | `ApiLevel.test.ets` | 2 |
| 2 | `BackgroundWorkPolicy.test.ets` | 1 |
| 3 | `CookieSession.test.ets` | 8 |
| 4 | `DeepLinkResolver.test.ets` | 6 |
| 5 | `HttpProbeClient.test.ets` | 5 |
| 6 | `QrLoginScanPolicy.test.ets` | 4 |
| 7 | `ReaderDocument.test.ets` | 9 |
| 8 | `RdbSchema.test.ets` | 3 |
| 9 | `ZhihuLoginClient.test.ets` | 9 |
| 10 | `ZseSigner.test.ets` | 3 |
| 11 | `AppStartup.test.ets` | 9 |
| 12 | `DomainModel.test.ets` | 10 |
| 13 | `DomainFixtureGate.test.ets` | 3 |
| 14 | `ZhihuHttpClient.test.ets` | 10 |
| 15 | `P1Persistence.test.ets` | 6 |
| 16 | `P1Navigation.test.ets` | 6 |
| 17 | `HomeFeedRepository.test.ets` | 7 |
| 18 | `HomeFeedState.test.ets` | 8 |
| 19 | `SessionRepository.test.ets` | 11 |
| 20 | `ZhihuQrLoginClient.test.ets` | 8 |
|  | **合计** | **128** |

提交前统一门禁实际执行 128 项；测试报告为 `Pass=128, Failure=0, Error=0, Ignore=0`。

## 本轮检查边界

- 仅修改统一测试入口和本清单，没有修改测试实现、生产代码、模块配置或测试依赖。
- 静态检查导入、默认导出和调用一一对应，并确认统一入口没有重复注册。
- 已使用 DevEco Studio 6.1.1/API 24 运行四模块构建和新鲜 Hypium 报告验证，未沿用历史结果。
