# P0 URL 与深链验证记录

> 验证日期：2026-07-20

## 解析边界

HarmonyOS 版本以 Android/Lite 的 `resolveContent()` 为兼容基线，使用纯 ArkTS 解析，不依赖网络或 ArkWeb。

| 输入 | HarmonyOS 目标 |
| --- | --- |
| `/question/{questionId}/answer/{answerId}`、`/answer/{answerId}` | 回答 |
| `/question/{questionId}` | 问题 |
| `zhuanlan.zhihu.com/p/{articleId}`、`/oia/articles/{articleId}` | 文章 |
| `/people/{urlToken}` | 用户 |
| `/video/{videoId}` | 视频 |
| `/pin/{pinId}` | 想法 |
| `/appview/answer`、`/appview/p`、`/appview/pin` | 对应内容 |
| `/search?q=...` | 搜索 |
| `link.zhihu.com?target=...` | 有限递归解包后重新解析 |
| `zhihu://answers`、`questions`、`articles`、`pin`、`search`、`feed` | 对应内容或首页 |

知乎已经使用超过 JavaScript 安全整数上限的 19 位内容 ID。解析结果因此始终以字符串保存，不转换为 ArkTS `number`。

解析器只接受精确的 `zhihu.com`、`www.zhihu.com`、`zhuanlan.zhihu.com` 和 `link.zhihu.com` 主机。伪造后缀域名、未知 scheme、非十进制内容 ID、未知路径和超过两层的跳转链接均拒绝。

## 系统接入

`EntryAbility` 在 `module.json5` 中声明 `ohos.want.action.viewData`、`entity.system.browsable` 和以下 URI：

- `zhihu://`
- `https://zhihu.com`
- `https://www.zhihu.com`
- `https://zhuanlan.zhihu.com`
- `https://link.zhihu.com`

冷启动在 `UIAbility.onCreate()` 读取 `Want.uri`，热启动在 `UIAbility.onNewWant()` 读取。日志只记录解析后的目标类型，不记录原始 URL、搜索词或内容 ID。

HTTPS skill 显式设置 `domainVerify: false`。项目不控制 `zhihu.com`，无法在该域名部署关联文件，因此不能把知乎网页链接宣称为已验证 App Linking；系统可能显示应用选择器。`zhihu://` 自定义 scheme 和应用内 URL 解析不受此限制。正式版本若需要无选择器跳转，应使用项目自有域名建立已验证 App Linking，再重定向到同一解析契约。

参考：[隐式 Want 启动 UIAbility](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ability-startup-with-implicit-want)、[UIAbility 生命周期](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/uiability-lifecycle)、[App Linking](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/app-linking-startup)。API 24 SDK 声明同时确认 `Want.uri` 自 API 9 可用、`UIAbility.onNewWant()` 自 API 10 可用，覆盖最低 API 20。

## 双版本虚拟机结果

| 验证项 | API 20 / HarmonyOS 6.0.0 | API 24 / HarmonyOS 6.1.1 |
| --- | --- | --- |
| 19 条完整 URL 映射矩阵 | 19/19 通过 | 19/19 通过 |
| 19 位 ID 保持原字符串 | 通过 | 通过 |
| URL 编码搜索词解码 | 通过 | 通过 |
| `link.zhihu.com` 目标解包 | 通过 | 通过 |
| `zhihu://` 隐式 Want 冷启动 | 通过 | 通过 |
| 已运行实例 `onNewWant` 热启动 | 通过 | 通过 |
| 首页新增入口与页面滚动 | 通过 | 通过 |

两台虚拟机页面均显示 `通过：19/19 条映射正确`，默认样本均显示 `回答：2040633177593619876`。隐式 Want 日志分别显示 `answer` 和 `question`，且不包含原始链接数据。

## 构建与测试

- API 24 SDK 下 Debug HAP：`BUILD SUCCESSFUL`。
- 新增 6 个解析契约测试，覆盖主要网页、19 位 ID、用户/视频/搜索、跳转链接、`zhihu://` 和非法输入。
- 当前 ArkTS 测试定义总数为 36；DevEco CLI 暂未暴露 `src/test` 本地单元测试任务，设备上的 19 条运行时矩阵用于补充验证，但不能替代后续 CI 测试入口。

主要 URL、`link.zhihu.com` 和 `zhihu://` 映射，以及系统冷/热启动分发均在 API 20/24 通过，因此 `P0-LINK-01` 标记为通过。
