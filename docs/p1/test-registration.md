# P1/P2 Hypium 测试注册

## 注册范围

`entry/src/test/List.test.ets` 保留全部既有导入和调用的相对顺序，并按“启动编排 → 领域模型与 fixture → HTTP → 持久化 → 导航 → P2 Feed/会话/搜索/详情/登录 UI”的语义顺序注册测试入口。

1. `domainFixtureGateTest()`：校验打包后的领域 fixture 清单、加载和解码门禁。
2. `zhihuHttpClientTest()`：校验共享 HTTP 会话、请求生命周期和结构化错误。
3. `p1PersistenceTest()`：校验 Preferences 与 RDB 持久化契约。

P2 新增的 Feed、会话、搜索、内容详情、登录 UI、频道、日报原生跳转、人员/想法详情、用户内容列表、屏蔽规则和已读历史测试入口同样只导入、调用一次；原有入口的相对顺序未改变。

## 源码静态计数

以下数量由各测试文件中行首 `it(` 调用静态计算得出，不沿用历史测试总数：

| 执行顺序 | 测试组 | `it()` 数 |
| ---: | --- | ---: |
| 1 | `ApiLevel.test.ets` | 2 |
| 2 | `BackgroundWorkPolicy.test.ets` | 1 |
| 3 | `CookieSession.test.ets` | 9 |
| 4 | `DeepLinkResolver.test.ets` | 7 |
| 5 | `HttpProbeClient.test.ets` | 5 |
| 6 | `QrLoginScanPolicy.test.ets` | 4 |
| 7 | `ReaderDocument.test.ets` | 9 |
| 8 | `RdbSchema.test.ets` | 4 |
| 9 | `ZhihuLoginClient.test.ets` | 9 |
| 10 | `ZseSigner.test.ets` | 3 |
| 11 | `AppStartup.test.ets` | 9 |
| 12 | `DomainModel.test.ets` | 10 |
| 13 | `DomainFixtureGate.test.ets` | 3 |
| 14 | `ZhihuHttpClient.test.ets` | 10 |
| 15 | `P1Persistence.test.ets` | 6 |
| 16 | `P1Navigation.test.ets` | 7 |
| 17 | `HomeFeedRepository.test.ets` | 8 |
| 18 | `HomeFeedState.test.ets` | 8 |
| 19 | `SessionRepository.test.ets` | 13 |
| 20 | `ZhihuQrLoginClient.test.ets` | 9 |
| 21 | `SearchRepository.test.ets` | 8 |
| 22 | `SearchState.test.ets` | 9 |
| 23 | `ContentDetailRepository.test.ets` | 6 |
| 24 | `ContentDetailState.test.ets` | 9 |
| 25 | `LoginController.test.ets` | 7 |
| 26 | `ChannelFeedRepository.test.ets` | 10 |
| 27 | `ChannelFeedState.test.ets` | 8 |
| 28 | `PeoplePinDetailRepository.test.ets` | 8 |
| 29 | `PeoplePinDetailState.test.ets` | 9 |
| 30 | `BlockingRuleMatcher.test.ets` | 7 |
| 31 | `BlockingRulesState.test.ets` | 5 |
| 32 | `ReadHistoryState.test.ets` | 5 |
| 33 | `DailyStoryRepository.test.ets` | 5 |
| 34 | `DailyStoryDetailState.test.ets` | 5 |
|  | **合计** | **237** |

第二批 P2 统一门禁实际执行 172 项；第三批和 P2 补齐切片接入后静态注册为 34 组、237 项，等待 DevEco Code `build_project` 生成新的执行报告。

## 本轮检查边界

- 仅修改统一测试入口和本清单，没有修改测试实现、生产代码、模块配置或测试依赖。
- 静态检查导入、默认导出和调用一一对应，并确认统一入口没有重复注册。
- 第二批已使用 DevEco Studio 6.1.1/API 24 完成四模块构建和新鲜 Hypium 报告验证；第三批不得沿用该历史结果，须以 `arkts_check`、`build_project` 与 API24 `start_app` 重新验收。
