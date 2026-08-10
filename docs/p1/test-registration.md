# P1 首批 Hypium 测试注册

## 注册范围

`entry/src/test/List.test.ets` 在原有十个测试入口之后追加以下 P1 测试，不改变原 46 项用例的入口和执行顺序：

1. `appStartupTest()`：AppStartup 初始化图、依赖顺序、幂等和失败隔离。
2. `domainModelTest()`：基础 DomainModel、知乎字段映射、字符串 ID、分页和错误边界。
3. `p1NavigationTest()`：强类型目的地名称、字符串参数和基础设施页面契约。

三个入口均使用对应测试文件的默认导出名称；每个入口只导入并调用一次。

## 预计用例数

| 测试组 | 用例数 |
| --- | ---: |
| P0 原有测试 | 46 |
| `AppStartup.test.ets` | 4 |
| `DomainModel.test.ets` | 9 |
| `P1Navigation.test.ets` | 3 |
| 合计 | 62 |

## 本轮检查边界

- 保留原有 `apiLevelTest()` 到 `zseSignerTest()` 的顺序。
- P1 测试统一追加在原测试之后，避免改变已验证门禁的初始化和执行顺序。
- 没有修改任何测试实现、生产代码、模块配置或测试依赖。
- 因 P1 模块拆分仍在移动源码，本轮只做注册和静态检查，不运行构建或 Hypium。

模块拆分稳定后，应使用 `docs/p0/environment-baseline.md` 中的 API 24 Hypium 命令运行完整测试，并同时检查命令结果和测试报告内容，确认实际执行 `62/62`。
