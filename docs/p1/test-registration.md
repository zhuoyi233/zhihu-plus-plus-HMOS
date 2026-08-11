# P1 Hypium 测试注册

## 注册范围

`entry/src/test/List.test.ets` 保留全部既有导入和调用的相对顺序，并按“启动编排 → 领域模型与 fixture → HTTP → 持久化 → 导航”的语义顺序补齐三个此前未注册的默认导出：

1. `domainFixtureGateTest()`：校验打包后的领域 fixture 清单、加载和解码门禁。
2. `zhihuHttpClientTest()`：校验共享 HTTP 会话、请求生命周期和结构化错误。
3. `p1PersistenceTest()`：校验 Preferences 与 RDB 持久化契约。

三个入口均只导入、调用一次；原有入口的相对顺序未改变。

## 源码静态计数

以下数量由各测试文件中行首 `it(` 调用静态计算得出，不沿用历史测试总数：

| 执行顺序 | 测试组 | `it()` 数 |
| ---: | --- | ---: |
| 1 | `ApiLevel.test.ets` | 2 |
| 2 | `BackgroundWorkPolicy.test.ets` | 1 |
| 3 | `CookieSession.test.ets` | 7 |
| 4 | `DeepLinkResolver.test.ets` | 6 |
| 5 | `HttpProbeClient.test.ets` | 5 |
| 6 | `QrLoginScanPolicy.test.ets` | 4 |
| 7 | `ReaderDocument.test.ets` | 9 |
| 8 | `RdbSchema.test.ets` | 3 |
| 9 | `ZhihuLoginClient.test.ets` | 9 |
| 10 | `ZseSigner.test.ets` | 3 |
| 11 | `AppStartup.test.ets` | 7 |
| 12 | `DomainModel.test.ets` | 9 |
| 13 | `DomainFixtureGate.test.ets` | 3 |
| 14 | `ZhihuHttpClient.test.ets` | 9 |
| 15 | `P1Persistence.test.ets` | 6 |
| 16 | `P1Navigation.test.ets` | 6 |
|  | **合计** | **89** |

其中原已注册入口当前共 70 项；本轮补齐的三个入口新增 18 项，冷启动未初始化导航栈契约新增 1 项，统一入口预计执行 89 项。

## 本轮检查边界

- 仅修改统一测试入口和本清单，没有修改测试实现、生产代码、模块配置或测试依赖。
- 静态检查导入、默认导出和调用一一对应，并确认统一入口没有重复注册。
- 本轮不运行构建或 Hypium；完整 API 24 Hypium 验证由主 agent 在并行实现合并稳定后执行，并以新鲜测试报告中的实际执行数和结果为准。
