# P4-5 前台视频播放状态机验证

验证日期：2026-08-20

## 交付范围

`VideoPlaybackState` 建模 idle、preparing、ready、playing、paused、completed、error 与 released，治理播放、暂停、seek、前后台、失败重试和 release 后迟到回调。实现不携带 Cookie 或任意自定义请求头，也不引入后台播放、下载或长时任务。

## 自动化证据

- `VideoPlaybackState.test.ets` 覆盖状态转换、非法/迟到回调、释放幂等和错误恢复；
- 主线集成 Hypium `457/457` 全通过；完整 HAP 构建成功，编译 API 26、target/compatible API 24。

## 已知限制与设备验收

当前为播放器生命周期状态机，生产页与平台播放器适配正单独接线。接线后须在 API 24 设备验证开始、暂停、seek、前后台、弱网、错误重试和离页 release，并确认没有后台音频或资源泄漏。
