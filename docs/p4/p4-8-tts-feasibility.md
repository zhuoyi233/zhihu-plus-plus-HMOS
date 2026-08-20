# P4-8 系统 TTS 可行性门禁

**结论：后置，不进入 P4 生产实现。**

截至本次门禁（2026-08-20），本工程所固定的 HarmonyOS API
`6.1.1(24)` 本地 SDK 中，没有找到可供普通应用稳定调用的公开文本转语音合成
API。因此不能仅凭“系统存在 TTS 设置”或网页声明就承诺“朗读”功能可用；P4-8 按
`docs/p4/p4-slicing-plan.md` 的后置分支完成，不阻塞其余 P4 切片。

这里的结论是“当前工程无法审计地确认可用”，并不声称设备系统一定不存在语音引擎。
在取得 API 24 的公开应用 API、依赖声明、权限/服务条款和真机回调证据前，不接入
未声明的模块、不猜测接口，也不把网页 Web Speech API 当作 ArkTS 应用能力。

## 1. 本地证据

本次仅离线检查了仓库和本机已安装的 SDK；没有读取 `ZHIHU_COOKIE`、没有发起网络
请求、没有启动设备或模拟器。

| 检查对象 | 结果 | 可审计含义 |
| --- | --- | --- |
| `build-profile.json5` | `targetSdkVersion` 与 `compatibleSdkVersion` 均为 `6.1.1(24)` | 门禁以项目实际 API 24 编译面为准，而非更高版本示例。 |
| `<SDK>/ets/api/*.d.ts` | 以 `TTS`、`TextToSpeech`、`text_to_speech`、`speechSynthesis` 检索，仅命中 `@ohos.settings.d.ts` | 该文件仅声明默认语速、音高、合成器和已启用插件等**设置键**；未声明创建引擎、提交文本、暂停、继续、停止或完成/错误回调。 |
| `<SDK>/ets/kits/*.d.ts` | 可用 Kit 清单中没有 `CoreSpeechKit` 或名称等价的 Speech/TTS Kit | 当前安装的 API 24 类型面无法形成可编译、可维护的 ArkTS 适配器。 |
| `entry/oh-package.json5` | 只有 `core`、`data`、`reader` 三个本地依赖 | 工程没有已锁定、可审计的第三方/厂商 Speech Kit 依赖。 |
| `entry/src/main/ets/platform/P4PlatformServices.ets` | 已有仅含 `speak/pause/resume/stop` 的占位 `SpeechService` | 它是架构预留，不是 API 24 能力证据，且不足以治理可用性、完成、进度和错误。 |

补充：SDK 内部 TypeScript 的 `lib.dom.d.ts` 中虽可见 Web Speech 类型，但它是 Web
DOM 类型库，不是本项目原生 ArkTS 的公开 `@kit`/`@ohos` 运行时契约；据此接入会产生
不可验证的编译或运行时依赖，故明确排除。

## 2. 现有 Reader AST 的安全输入边界

`reader/src/main/ets/reader/ReaderDocument.ets` 已将知乎 HTML 解析为 `ReaderBlock`，其
`ReaderBlockKind` 包含 `HEADING`、`PARAGRAPH`、`LIST_ITEM`、`DIVIDER`、`FORMULA` 和
`IMAGE`，并为含公式的段落维护 `ReaderInlineRun`。详情页 `NativeContentDocument` 也已
使用同一 AST 渲染正文。

若后续门禁通过，TTS 输入必须由一个纯函数从该 AST 派生，而不是接收 HTML 或 URL：

- 仅接受可见的 `HEADING`、`PARAGRAPH` 和 `LIST_ITEM` 的文本；分隔线和图片一律跳过；
- `FORMULA` 块与 `ReaderInlineKind.FORMULA` 内联 run 一律跳过，不能朗读公式 URL、TeX
  或图片 URL；含内联公式的段落只拼接其中的 `TEXT` run；
- 保留原始块 id 到分段 id 的映射，只在内存中保存本次会话的纯文本；不回写 Reader
  缓存、草稿、RDB、日志或分析事件；
- 分段上限必须以未来获得的引擎公开限制和真机结果确定，当前没有可靠证据，禁止编造
  固定字符阈值。

## 3. 未来实现的最小安全契约和生命周期

现有占位接口在门禁通过后应收敛为能力驱动的适配器；系统对象不得穿过组合根。最小
契约至少需要表达下列事实，而不是仅返回一个无法观察完成的 `Promise<void>`：

```ts
interface SpeechAvailability {
  readonly available: boolean;
  readonly reason: string;
  readonly requiresNetwork: boolean;
}

interface SpeechProgress {
  readonly segmentId: string;
  readonly state: 'playing' | 'paused' | 'stopped' | 'completed' | 'failed';
  readonly errorMessage: string;
}

interface SpeechService {
  checkAvailability(): Promise<SpeechAvailability>;
  start(segments: Array<SpeechSegment>, onProgress: (value: SpeechProgress) => void): Promise<void>;
  pause(): void;
  resume(): void;
  stop(): void;
  release(): void;
}
```

正式 ArkTS 实现时需改为项目允许的显式类型形式；此处只说明边界，不是待编译代码。
`SpeechSegment` 只含临时 id 和上述 AST 过滤后的纯文本。

生命周期不可放宽：

1. 用户明确点击“朗读”后才 `checkAvailability` 和 `start`；失败只显示通用错误，不回显正文。
2. 重复开始先 `stop` 并使旧回调失效；只允许一个前台会话和一个串行分段队列。
3. 页面 `aboutToDisappear`、内容切换、应用进入后台、音频焦点丢失或能力错误时，默认
   `stop` 后 `release`；不申请后台长时任务，不自动恢复。
4. 只有同一页面仍在前台且会话 token 未过期时，才可 `pause/resume`；完成、停止和失败
   都清空内存分段及回调引用。

## 4. 隐私与安全限制

- 不读取、不传递 Cookie、Authorization、自定义请求头、用户标识或原始 HTML；
- 不记录正文、分段内容、语音回调原文、公式/图片 URL；诊断最多记录非内容错误码和会话
  状态，且不得与账号关联；
- 在无法证明引擎完全离线时，默认视为可能向网络传输正文：必须提供独立隐私说明和关闭
  状态的用户开关，且未获得明确同意前不得调用；
- 不为 TTS 增加 `INTERNET` 以外的权限、更不因朗读请求后台常驻、录音或媒体库权限；
- 当前详情菜单继续保留禁用的“朗读（开发中）”入口，不能把它接到 WebView、第三方网页
  或未审计 Intent/WanT。

## 5. 通过门禁所需的后续证据

在单独切片重新开启 P4-8 前，必须同时满足：

1. API 24 SDK/官方离线文档可定位到公开模块、引擎创建、文本提交、停止/释放及完成、错误
   回调；依赖版本、适用设备、权限和服务条款均可写入锁文件与设计文档。
2. 至少一台 API 24 目标设备在飞行模式和联网两种情形下验证中文短文、长文分段、暂停、
   继续、停止、页面离开、后台、音频焦点抢占和引擎缺失；质量、回调顺序和资源释放均稳定。
3. 若任一模式要求联网或服务端处理，先完成隐私说明、默认关闭开关和“正文不落盘/不入日志”
   审查；离线可用也仍需验证不产生隐藏网络请求。
4. 在 `reader` 中加入纯函数分段与过滤单测，在 `entry` 中对 fake `SpeechService` 覆盖
   取消、过期回调、错误、重复开始和生命周期释放；随后按项目脚本完成编译、Hypium 与真机
   验证。

任一条件不满足即维持本后置结论。P4 的完成判定不依赖 TTS，避免把不确定的系统或云服务
能力变成阅读主路径的可靠性和隐私风险。

## 6. 本次验证

- 文档结构检查：标题、API 24 结论、AST 输入、生命周期、隐私限制、通过条件均已检索确认；
- `git diff --check`：无空白错误；
- 未改动源码、依赖、权限或构建配置，因此未运行会改变 SDK/构建缓存的完整构建；本切片的
  可验证交付物仅为上述离线门禁文档。
