# P2 图片预览交互

## 已实现

- 正文图片来源继续限制为 `https://pic*.zhimg.com/` 和 `https://picx.zhimg.com/`。
- 预览支持双指缩放，范围为 1x 到 4x；双击恢复 1x。
- 预览提供保存、分享、关闭按钮；长按图片等价于保存。
- 保存前请求 `ohos.permission.WRITE_IMAGEVIDEO`，下载响应限制为 8 MiB、禁止重定向，写入系统相册使用 API24 `MediaAssetChangeRequest`。
- 分享使用 API24 `Want` 的 `ACTION_SEND_DATA`，只分享受信图片 URL，不携带 Cookie、页面正文或请求头。
- 保存失败、权限拒绝、分享能力不可用均只显示固定提示，不显示原始异常或响应内容。

## API24 验收清单

- [ ] Pura 90/API24：单击图片进入预览，关闭按钮返回正文。
- [ ] Pura 90/API24：双指缩放不超过 4x，双击恢复原始大小。
- [ ] Pura 90/API24：长按或保存按钮弹出相册授权；授权后 JPEG/PNG/GIF/WEBP 均能在相册出现。
- [ ] Pura 90/API24：分享按钮能打开系统分享面板，取消后回到预览。
- [ ] Pura 90/API24：拒绝相册权限、断网、超过 8 MiB 和非知乎图床地址均显示固定失败提示。
- [ ] 200% 字体和折叠屏宽度下，底部操作按钮不裁切，图片仍可关闭。
