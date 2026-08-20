# P4-2 图片上传协议合同验证

验证日期：2026-08-20

## 交付范围

- `ImageUploadContracts` 对 JPEG、PNG、WebP、GIF magic bytes 和尺寸进行受限识别，并执行单文件、批次与内存门禁；
- `cache/p4-images` 临时资源状态机只处理受控本地引用；
- 将申请、单 PUT、GIF 分片、状态通知和受信知乎图床轮询固定为纯函数合同；
- HMAC-SHA1 Base64 仅作上游协议兼容，上传凭证不进入持久化、日志或测试报告。

## 自动化证据

- `ImageUploadContracts.test.ets` 覆盖格式、限额、临时资源、单图/GIF 协议、受信 URL 与异常路径；
- 集成主线执行 `pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -SkipBuild`，Hypium `457/457`；
- 随后完整执行 `pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall`，生成 API 26 编译、API 24 target/compatible 的签名 HAP。

## 已知限制与设备验收

本切片冻结输入和上传协议，尚未以真实账号发送上传请求。后续 Photo Picker 接线须在 API 24 设备验证 JPEG、PNG、WebP、GIF、超限、取消、断网和后台恢复；任何真实上传均使用专用测试内容，且不得记录 Cookie、临时凭证或图片正文。
