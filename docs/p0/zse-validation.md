# P0 ZSE96 v2 验证记录

> 验证日期：2026-07-20

## 验证范围

- Android/KMP 基准实现：`shared/src/commonMain/.../ZseSigner.kt` 与 `ZhihuFetchSignature.kt`。
- HarmonyOS 实现：`entry/src/main/ets/network/ZseSigner.ets`、`Md5.ets` 与 `ZhihuFetchSignature.ets`。
- 实现为纯 ArkTS，不依赖端侧 AI、Native 库或远程签名服务。

## 黄金向量

| 项目 | 输入 | 预期输出 |
| --- | --- | --- |
| ZSE v4 | `hello` | `+6xPvLM9SJjT+GToL9YAivj/` |
| ZSE v4 | `world` | `+65CcmGtmyq0DMsf4jUsBidi` |
| ZSE96 | 固定 zse93、URL、d_c0 和 JSON body | `2.0_XAY8F0Fc/7DSnpGxJblUS2S4BuUCOnxIL4t+Dzd/+=mp3=CL74Cwu=t0WDQ/iOYG` |

完整 ZSE96 输入：

```text
zse93 = 101_3_3.0
url   = https://www.zhihu.com/api/v4/me?include=account_status
d_c0  = fixed-d_c0-token
body  = {"hello":"world"}
```

黄金值通过本机 Kotlin 编译器直接编译仓库中的 `ZseSigner.kt` 生成，不使用 ArkTS 实现反向生成期望值。Android shared 全模块 JVM 测试曾因 Google Maven TLS 握手失败无法完成依赖下载；该外部依赖问题不影响隔离执行算法源文件。

## HarmonyOS 结果

- MD5 标准向量 5 个通过，覆盖 ASCII、中文和四字节 UTF-8 字符。
- ZSE v4 Android 黄金向量 2 个通过。
- 完整 `x-zse-96` Android 黄金向量 1 个通过。
- 连同 API 版本和 HTTP 分类测试，ArkTS 共 8 个用例，失败 0。
- Debug HAP 构建通过。

P0-ZSE-01 已满足“与 Android 向量逐字节一致”的通过条件。实际知乎请求仍需要合法 Cookie 中的 `d_c0`；这属于 P0-SES-01 与 P0-LOGIN-01，不能用固定测试 token 替代。
