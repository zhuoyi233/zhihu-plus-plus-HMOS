# P4-5 视频播放页首个切片验证

## 本切片范围

- `P1DestinationName.VIDEO` 已由 P4-0 提供；本切片将其接入 `P1Shell` 与组合根，进入可见的视频播放页。
- 页面只接收内容 ID 和可注入的 `VideoSourceResolver` / `VideoPlayerAdapter`，不会从 ID 拼接媒体地址、读取 Cookie，或主动发起网络请求。
- 未有受信任播放源时，默认解析器返回空值并显示安全提示；这是当前生产默认路径。
- 控制器将 `prepare`、播放、暂停、seek、结束、错误与释放统一收束到 `VideoPlaybackState` 的 generation 门禁；页面消失时立即 release，迟到回调不会污染已释放页面。

## API 24 核验与后续设备门禁

已在本机 API 24 SDK 类型声明 `@ohos.multimedia.media.d.ts` 核验 `media.createAVPlayer`、`AVPlayer.url`、`prepare`、`play`、`pause`、`seek` 和 `release` 存在。视频画面还必须通过 `XComponent` surface 与 `AVPlayer.surfaceId` 的联合设备验收；本切片未猜测该绑定，也未让默认路径创建播放器。

后续实现真实 adapter 前，必须在 API 24 设备验证：

- HTTPS 受信任媒体地址播放、暂停、seek、结束与重复 release；
- 前后台、页面返回、横竖屏、低内存与弱网时资源释放及 generation 门禁；
- 真实内容播放地址仅由数据层白名单解析，日志、错误 UI 和测试 fixture 不记录 URL token、Cookie 或请求头。

## 自动化验证

新增 `VideoPlaybackController.test.ets`：覆盖缺失播放源不会调用播放器、页面释放后迟到 `onReady` 回调被丢弃。执行：

```powershell
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -SkipBuild
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall
```
