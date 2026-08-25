# P4-5 API 26 视频播放设备验收

## 范围与安全边界

本记录只覆盖 HarmonyOS API 26 模拟器 `ZhihuPlus_API26`（`127.0.0.1:5555`，
HarmonyOS 7.0.0 / API 26）。它验证的是页面与平台播放器的接线，不把知乎内容 ID
转换为媒体地址，也不向知乎或任何第三方发起媒体探测请求。

`Api26VideoPlayerAdapter` 只有 URL、XComponent surface、播放控制和生命周期这四个输入；
没有 Cookie、Header 或网络配置入口。`VideoSourceResolver` 仍是唯一能提供已审计播放源的
数据层边界。当前仓库没有这样的解析器，因而默认 resolver 必须返回空值。

## 已执行的 API 26 验收

1. 用本地调试签名构建 HAP，并覆盖安装到 `ZhihuPlus_API26`；安装与启动成功。
2. 通过应用已声明的 HTTPS 深链启动：

   ```powershell
   aa start -a EntryAbility -b com.github.zhuoyi233.zhplus `
     -A ohos.want.action.viewData -U https://www.zhihu.com/video/123456789
   ```

3. 使用 `devecocli ui layout` 读取到 `p4_video_surface`，节点类型为 `XComponent`；
   页面表明 surface 已创建而不是旧的文本占位符。
4. 读取到 `p4_video_playback_status` 为“该视频暂时没有可用的受信任播放源”。页面不创建
   `AVPlayer`、不调用网络，播放按钮保持不可用。
5. 截图人工复核：黑色 XComponent 画面区域、视频 ID 和安全提示均可见；返回页面后由
   `aboutToDisappear` 释放控制器，surface 销毁也会走同一释放路径。

这证明 API 26 的 XComponent lifecycle 已接到页面，且未知内容不会越过数据层安全边界。
它不声称已播放真实知乎视频。

## 受控媒体 fixture 的后续设备注入

要验收真实的 `prepared → play → pause → seek → completed → release`，测试人员必须先提供：

- 经所有者明确批准、可复现的 HTTPS 媒体 fixture；
- 被数据层白名单批准的 host、固定内容 ID 与失效时间；
- 不含 URL token、Cookie、Header 的验收记录和日志。

在**不提交 fixture URL**的本地测试分支，给 `VideoPlaybackPage` 注入仅返回该固定
`VideoPlaybackSource` 的 `VideoSourceResolver`；不要传入自定义 `player`，页面会在
`XComponent.onLoad` 后自动创建 `Api26VideoPlayerAdapter(surfaceId)`。验收时依次观察：

1. `prepared` 后启用播放，时长显示为正数；
2. 播放、暂停、拖动 seek 后状态和时间更新；
3. 播放结束进入 completed；
4. 返回上一页、旋转或销毁 surface 后，再触发的播放器回调不会改变已释放页面。

若 fixture 不可用，继续保留本记录的安全拒绝结果；不得以猜测知乎接口、硬编码 URL、
附加 Cookie/Header 或自动外部请求替代该验收。

## 自动化依据

- `Api26VideoPlayerAdapter.test.ets`：surface 绑定、原生状态/时间回调、release 后迟到
  回调、空 surface 拒绝；
- `VideoPlaybackController.test.ets`：generation 门禁、播放/暂停/seek 和注入时间回调；
- API 26 Hypium：`487/487` 通过。
