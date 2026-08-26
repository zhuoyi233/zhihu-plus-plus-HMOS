# P4 API 26 最终实现与验收记录

执行日期：2026-08-26。目标设备：`ZhihuPlus_API26`（`127.0.0.1:5555`）。

## 已完成的代码闭环

- 回答新建/编辑和想法发布均接入生产 `ZhihuHttpClient` 仓储；页面首次点击只显示最终确认，只有用户再次点击“确认发布”才会开始任何外部写入。
- 图片仅在最终确认后按“本地加密草稿 → 知乎图片申请/OSS 上传/状态轮询 → 远端草稿 → 正式发布”执行。OSS 请求不带 Cookie 或 ZSE，临时凭证不持久化。
- 已保存草稿只记录受控缓存随机文件名和已验证元数据。重新打开时可恢复预览和上传引用；取消、失败或离页不会用空选图状态覆盖这些引用。
- 上传失败不会调用远端草稿或正式发布；回答和想法的状态机测试均覆盖该门禁。离页会取消活动上传并拒绝迟到回写。
- 电脑端登录扫码确认页只接收经严格策略校验的链接，限制为 HTTPS `www.zhihu.com` 主框架导航；关闭、离页或进入后台会清除链接并停止 ArkWeb。
- 视频、系统分享和 TTS 后置可行性结论沿用各自 P4 验证文档；P4-8 没有进入生产 TTS 实现。

## 自动化与构建证据

在主线 `dev` 执行：

```powershell
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -SkipBuild
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall
```

- API 26 Debug HAP 签名构建成功；`pack.info` 为 `target=26`、`compatible=26`，bundle 为 `com.github.zhuoyi233.zhplus`。
- Hypium 直接完整执行结果：`516/516` 通过（Failure=0，Error=0，Ignore=0）。
- 覆盖新增的回答/想法“本地草稿先行、上传成功才远端发布、上传失败保留引用”和草稿图片恢复/追加选择门禁。

## API 26 模拟器安全回归

安装签名 HAP 后启动 `EntryAbility`，使用已有登录态完成以下无写入检查：

1. 首页刷新后 `p2_home_feed_list` 可见，`p2_home_error_login` 与 `p2_home_error_retry` 均不存在。
2. 设置页打开想法编辑器后，`p4_pin_publish_page`、标题/正文输入、`p4_image_picker_select` 和 `p4_pin_publish_submit` 均可见，未出现登录 CTA。
3. 未输入正文、未选图、未保存草稿、未点击发布确认；本地/设备布局 dump 已删除且未进入 Git。

## 需要用户手动完成的外部状态验收

这些动作会创建知乎内容或改变电脑端登录状态，不能由自动化 Agent 执行：

1. 使用可丢弃的专用账号分别验证文本回答、带图回答、编辑回答并重启恢复。
2. 分别验证文本想法、带图想法、带话题想法及上传失败后重试；确认最终确认前没有网络写入。
3. 验证 Scan Kit 扫描真实电脑端登录码，并在受限确认页由用户完成或取消确认。
4. 验证视频真实播放和至少两个系统分享目标的取消/完成路径。

记录仅保留时间、API 26 设备、结果和脱敏内容 ID；不得记录 Cookie、正文、原图、OSS 凭证或原始响应。
