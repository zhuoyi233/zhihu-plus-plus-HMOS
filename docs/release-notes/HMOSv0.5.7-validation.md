# v0.5.7 发版验证

验证日期：2026-10-03。发版准备基线：`4bd13f913fe754d7a013a18c00ff4079ae7c7362`。

## 包体积

比较对象均为未签名 HAP；v0.5.6 本地文件的 SHA-256 与 GitHub 已发布附件一致。

| 版本 | 字节数 | MiB | 构建模式 |
| --- | ---: | ---: | --- |
| v0.5.6 | 7,844,629 | 7.48 | Debug |
| v0.5.7 | 3,147,554 | 3.00 | Release |

减少 4,697,075 字节，约 **59.9%**。其中字节码减少 2,303,312 字节，源码映射移出安装包减少 2,397,230 字节；其他元数据与更新清单有少量增长。

v0.5.7 未签名发行包 SHA-256：

`1dc4f50fdec3c89d6001dd1c620e9367e6dec7952f24fb7d59775e22e5c6520b`

## 构建与测试

依次执行仓库规定的三个验证命令：

1. `pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -SkipBuild`：通过，Hypium 721/721。
2. `pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall`：Debug 构建、签名与 Hypium 721/721 通过。
3. `pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -BuildMode release`：最终完整通过，Hypium 721/721；版本 0.5.7/1000507、target API 26、compatible API 23、`debug=false` 均通过校验。

Release 前两次运行的报告汇总均为 721 项通过，但原始记录出现额外 `test=` 行及日志字符混入，严格计数校验拒绝出包；保留报告后重新运行完整流程，第三次原始记录、结果与汇总均为 721，门禁未修改。日志和原始报告保存在本地 `entry/build/`，不提交。

发行 HAP 不含 `ets/sourceMaps.map`，源码映射已归档到本地构建目录。版本命名产物与构建产物的 SHA-256 一致，签名包仅供本机调试。

## 设备验证限制

已启动 `ZhihuPlus_API23`，实际连接地址为 `127.0.0.1:5557`，设备 API 查询为 23。尝试覆盖安装 Release 签名包时，系统返回 `9568332 / install sign info inconsistent`；保留现有应用及数据，未卸载。本次不宣称完成安装、冷启动或页面烟测。

## 发布清单与后续步骤

构建前已使用 `-SeedPending -Version 0.5.7` 写入发布说明，发行 HAP 内含本版本更新内容。构建完成后重新生成两份已发布版本清单，PR 不携带无附件的 0.5.7 占位条目。

重新构建发行包时，应先按仓库流程预置说明。正式发布仍需确认 Release 草稿，发布后附上未签名 HAP，并重新生成包含真实附件 URL、大小与 SHA-256 的两份更新清单。
