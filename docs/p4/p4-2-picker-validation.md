# P4-2 系统媒体选择首个生产适配切片

日期：2026-08-20
范围：只交付系统选图到 P4-2 上传合同之间的可注入协调层；不接入发布页面、真实上传或用户 Cookie。

## 已冻结边界

- `SystemPhotoPickerGateway` 只会由用户显式点击后的组合根调用；返回取消时不产生本地引用或网络行为。
- `PickedImageInspector` 只读取有限的头部和长度，交给 `ImageUploadContracts.validatePickedImageBatch` 进行 magic bytes、数量、单文件/批次大小、像素和解码内存门禁。
- `PickedImageTemporaryStore` 只能生成 `cacheDir/p4-images` 内的受控临时文件；协调层复核 MIME 与字节数，随后才将受控文件生命周期交给创作草稿/上传流程。
- 取消、释放、写入失败和迟到 Picker 结果均不保留用户 URI；已生成的受控缓存会通过 store 删除接口清理。不会读取 Cookie，也不会发送请求。

## API 24 门禁结论

本切片不猜测 Photo Picker Kit 的 API 24 可用签名。生产 `SystemPhotoPickerGateway` 必须在 API 24 真机确认以下内容后才可接入：

1. 用户显式唤起时能返回仅选中媒体的可读 URI，且不申请全量相册读取权限；
2. 取消和权限拒绝可映射为 `PhotoPickerResultKind.CANCELLED`，不把系统原始错误显示给用户；
3. 选中 URI 可以被受控缓存写入器以流式方式读取、关闭并生成随机文件名；
4. JPEG、PNG、WebP、GIF、超限文件、切后台和断网均通过设备回归。

在这些门禁通过前，组合根只能注入 fake gateway；页面和发布流不得直接调用未审计的 Photo Picker API。

## 自动化覆盖

- 显式选择的 JPEG/PNG 经过 magic/限额检查后才写入受控缓存；
- Picker 取消、未知格式、超限和临时写入失败都不产生可用选择结果；
- 取消/释放删除缓存，迟到 picker 结果不回写；
- 测试 fake 不读取文件、Cookie 或网络。
