# P0 Cookie 会话安全验证记录

> 验证日期：2026-07-20

## 存储方案

- Cookie 会话序列化后使用 AES-256-GCM 加密，每次写入生成独立的 12 字节随机 IV。
- GCM AAD 固定绑定 Bundle Name 与会话格式版本，避免密文被移用于其他应用或格式。
- AES-256 数据密钥由 Crypto Architecture Kit 生成，并作为敏感资产保存到 Asset Store。
- Preferences 只保存版本、IV、密文和 GCM 认证标签组成的信封，不保存 Cookie 明文或数据密钥。
- 密钥禁止设备同步，访问级别为设备首次解锁后可用；退出登录时同时删除密文与密钥。
- 解密、解析或认证失败时按损坏会话处理，删除密文并返回游客会话。

该方案依据 HarmonyOS 官方的 [Asset Store Kit](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/asset-store-kit-overview)、[Crypto Architecture Kit](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/crypto-introduction) 和 [Preferences](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/data-persistence-by-preferences) 能力设计。

## Cookie 语义

- 手动 Cookie 字符串解析会忽略 `Domain`、`Path`、`Expires`、`Max-Age`、`HttpOnly`、`Secure` 和 `SameSite` 属性。
- Cookie 值允许包含 `=`。
- Cookie 名称和值会拒绝 CR/LF、NUL、分号和非法名称字符，避免请求头注入。
- 与 Android Lite 行为一致：服务器返回空 `z_c0` 时保留现有有效值。
- 每次保存和读取都会移除 `expiresAt` 不晚于当前时间的 Cookie。
- 请求 Cookie Header 只包含未过期、非空 Cookie。

## 日志约束

- 业务日志只能调用会话摘要接口，摘要仅包含 Cookie 数量和名称，不包含值。
- 通用脱敏函数覆盖 `Cookie`、`Set-Cookie`、`Authorization`、`x-zse-96`、`z_c0`、`d_c0` 和 `_xsrf`。
- P0 UI 和虚拟机验证结果均未显示、输出或导出测试 Cookie 值。

## 自动化结果

Cookie 会话新增 6 个 ArkTS 用例：

1. Cookie 解析与属性过滤。
2. 过期清理与 Header 生成。
3. 空 `z_c0` 更新保护。
4. 请求头注入字符拒绝。
5. 会话格式序列化往返。
6. 日志脱敏与安全摘要。

连同 API 版本、HTTP 和 ZSE96 测试，ArkTS 共 14 个用例，失败 0。Debug HAP 构建通过。

## DevEco 虚拟机结果

| 虚拟机 | 写入加密会话 | 进程重启恢复 | 过期清理 | 会话与密钥清理 |
| --- | --- | --- | --- | --- |
| `ZhihuPlus_API20` | 通过 | 通过 | 通过 | 通过 |
| `ZhihuPlus_API24` | 通过 | 通过 | 通过 | 通过 |

P0-SES-01 已满足通过条件。当前原型使用合成 Cookie，仅验证会话安全和生命周期；真实 Cookie 导入、登录验证和失效恢复属于 P0-LOGIN-01。
