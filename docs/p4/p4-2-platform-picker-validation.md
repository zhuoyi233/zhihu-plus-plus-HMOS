# P4-2 Photo Picker 平台适配验证

日期：2026-08-20
范围：把官方系统选图能力接到既有 `SystemPhotoPickerGateway` 窄接口；不接页面、发布流、文件读取器或网络。

## SDK 依据

已检查本机 API 24 SDK 的 `@ohos.file.photoAccessHelper.d.ts`：

- `photoAccessHelper.PhotoViewPicker` 与其 Promise 形式的 `select(option?)` 自 API 10 提供；
- `PhotoSelectOptions.MIMEType`、`maxSelectNumber` 与 `PhotoViewMIMETypes.IMAGE_TYPE` 也都自 API 10 提供；
- 返回 `PhotoSelectResult.photoUris`，SDK 注释限定其只可由 PhotoAccessHelper 按授权使用。

生产适配 `HarmonyPhotoPickerClient` 因此仅传入 `MIMEType: IMAGE_TYPE` 和调用方的 `maxSelectNumber`。没有加入未核实的编辑、拍照、预选、媒体库权限或 API 24 之后字段。

## 受控 URI 边界

- 平台结果先经 `HarmonySystemPhotoPickerGateway` 收缩：最大数量、空 URI 和重复 URI 被处理；不会将 display name、MIME、媒体资产对象或系统错误穿过接口。
- URI 只作为随后的 `PickedImageInspector` 的输入；它不能作为路径或 MIME 信任来源。P4-2 已有的 magic bytes、字节数、像素和缓存写入门禁继续负责实际可用性。
- 系统取消、空结果、非法数量和平台异常统一映射为 `PhotoPickerResultKind.CANCELLED`，不保留或展示原始错误。
- 本适配不读取 Cookie，不请求 `READ_IMAGEVIDEO`，不发网络请求，也不执行文件读写。

## 自动化与设备门禁

Hypium 使用可注入 `SystemPhotoPickerClient` 验证：数量参数、URI 去重/上限、空选择、非法上限以及错误脱敏。测试不启动系统 Picker。

API 签名已由本地 SDK 证实；仍需在 API 24 设备手动确认：用户点击后是否打开系统照片页、取消是否返回空 `photoUris` 或 reject、选中 URI 是否能被后续受控 inspector 流式读取，以及多选上限是否由系统界面兑现。未通过这些设备项前，组合根不得把适配器接入页面。
