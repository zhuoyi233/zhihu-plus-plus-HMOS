# 鸿蒙版静态更新清单

应用检查更新时优先读取 `assets/update/version.json`，发布说明读取
`assets/update/releases.json`。两者先经 GitHub Raw 与 jsDelivr/Fastly 镜像
并行获取；4 秒内仍无有效响应，再叠加与「系统与更新」页共用的 17 个下载代理
（前缀拼接 raw 直连地址，含同样的 10 分钟防缓存参数）竞速，首个结构有效响应
获胜，并使用 10 分钟进程内缓存。不支持 raw 路径的代理返回的 HTML 错误页会被
结构校验计入失败，无需维护支持性白名单。静态源与代理全部不可用时，版本检查
回退到 GitHub Releases Atom；HAP 内置清单提供离线兜底。
运行时不请求 `api.github.com` 的 Release 接口。

每个版本将版本号与 `docs/release-notes/HMOSv<x.y.z>.md` 一起提交，PR 前按顺序通过
编译/Hypium、Debug 与 Release 验证。合入 `main` 后，先在待发版提交再次执行正式出包命令：

```powershell
pwsh -NoProfile -File scripts/verify-harmony.ps1 -SkipDependencyInstall -BuildMode release
```

验证通过后，确认 HEAD 仍是该提交且没有待发布的源码改动，再由维护者手动在该 `main` 提交创建
`HMOSv<x.y.z>` 附注 tag。创建 Release 草稿时使用这次验证通过的 HAP；如源码或提交有变化，先重新验证。
tag 后如需重建，必须检出 tag 对应提交并重新运行上述命令，不能以之前的验证结果代替。
这仅适用于包含新版脚本的 tag。旧 tag 自带旧脚本，应按当时文档与工具链重建；例如 0.5.6 的脚本
尚无 `-BuildMode`，不会运行新增的文稿检查。将新版构建能力移植到历史源码时，缺少归档文稿可传
`-NotesFile <本地文稿>`（相对路径以仓库根目录为准），文稿须先核对且通过相同版本标题/正文校验。
脚本不隐式从网络获取可变的发布说明，使用此参数时创建 Release 草稿也应复用同一文稿。

脚本要求文稿首行为 `# ZhihuPlusPlus-HMOS v<versionName>` 且包含正文，缺失或版本不符时拒绝构建。
Release 打包期间自动将当前文稿与已发布历史合并到 HAP 内置的 `update/version.json` 和
`update/releases.json`，为当前版本提供离线更新说明。历史始终按版本降序，`version.json` 等于历史首项，
重建旧版本时保留已知更高版本；离线检查提示已知更新，不将旧版本误报为最新。内置版本与本机相同时
保留原有“已是最新版本”兜底；内置数据旧于本机或无效时报告检查失败。
临时资源在正常结束或异常抛出时由 finally 恢复，`assets/update/` 不参与构建期改写；正常工作树中的两份清单
仍保持相同的正式发布数据。因此从 `main` 或 tag 重新构建无需手动预置，也无需提交占位清单。
旧 `update-release-catalog.ps1 -SeedPending` 模式已移除。
强杀进程或断电可能留下临时资源。每次注入前逐文件对比两处清单 SHA-256，不一致或缺失时中止，
提示可能是注入残留。先检查 `git diff` 并备份有意改动，再恢复 rawfile 清单与在线清单一致；脚本不会自动覆盖现场。

当前包无法预先知道自身 SHA-256，内置当前条目不携带附件信息，重建已发布版本时也会清除旧附件哈希。
在线下载与校验使用正式发布后生成的清单。发布说明文稿与 `gh release create --notes-file`
复用同一文件，保证应用内展示与 Release 页一致。

构建与 Hypium 通过后，脚本在复制版本命名产物前解压检查未签名和签名 HAP：
历史清单必须包含唯一的当前版本、完整正文与文稿一致，当前条目不得带有旧附件元数据。
同时检查历史降序以及 `version.json` 与历史首项一致。
说明缺失、版本错误、正文不完整或残留旧哈希均导致交付失败。
正式交付必须使用该命令，不能把 DevEco/devecocli/hvigor 裸构建产物直接当作已验证发行包。
交付记录须包含完整路径、版本、大小和 SHA-256，避免不同工作树的同名文件混用。
Release 日志包含构建前后的 HEAD 和 `git status --porcelain`；两次状态不一致时拒绝交付。
存在未提交改动时会告警，允许本地验证，正式发版须先提交再重建。成功后生成
`<未签名HAP路径>.build.json`，记录前后 Git 状态、文稿 SHA-256、覆盖文稿参数以及 HAP 路径/大小/SHA-256。
打 tag 与上传前核对记录中的提交、干净状态和实际包摘要；被忽略及 skip-worktree 文件不在 Git 状态中，
记录不能证明脏工作区内容或本地工具链可复现。
创建 Release 时先保存草稿，正式发布仍需维护者当次明确确认。

每次正式 Release 发布后，维护者运行：

```powershell
pwsh -NoProfile -File scripts/update-release-catalog.ps1
```

脚本读取已发布的 `HMOSv*` Release，排除草稿、预发布和上游 Android tag，
并写入真实附件 URL/大小/SHA-256、发布时间，同时更新仓库静态清单与 HAP 内置清单。
写入前必须验证每个版本有唯一的 `ZhihuPlusPlus-HMOS-v<version>-unsigned.hap`，附件版本与 tag 一致，
URL 对应当前仓库、tag 和文件名，大小为正整数，GitHub digest 为完整的 SHA-256。
任何版本校验失败或 API 请求失败均中止，不覆盖原清单；`releases.json` 在单版本时也保持数组结构。
历史附件损坏时优先恢复附件。如果决定撤下该历史版本，可显式传
`-ExcludeReleaseTag HMOSv0.5.6`（多项用 PowerShell 数组）；脚本告警并从在线与随包清单移除此版本，
保留其他版本的严格校验。不能排除最新正式版本或未知 tag；该选项不持久化，下次生成需再次明确指定，
提交清单时记录撤下原因。没有全局跳过附件校验的开关。
应核对最新版本、未签名 HAP 附件与发布说明，再随下一次代码变更提交；用户明确要求时可单独提交/创建 PR。
在线清单只保存正式发布数据，禁止提交构建期占位条目。远端 `main`
包含新清单后，旧版客户端也能发现该版本。若清单尚未部署，Atom 可发现新版本，
但下载源会等到附件元数据可用时才展示。

若替换正式 Release 的 HAP 附件，即使版本号与下载 URL 相同，其大小或 SHA-256 也会变化。
替换后必须再次运行清单脚本、核对新附件摘要，并经授权提交/推送更新；旧清单会使新附件下载校验失败。
清单描述的是已发布包，不要求将它重新塞进该包再替换附件，否则每次重打包都会改变摘要。

构建期注入、资源恢复、损坏包拦截及正式清单生成的脚本回归验证（清单测试使用模拟 API，不访问网络）：

```powershell
pwsh -NoProfile -File scripts/test-release-notes.ps1
pwsh -NoProfile -File scripts/test-release-catalog.ps1
```

页面的 18 个下载源由同一条真实未签名 HAP URL 生成：前 17 个为代理，
最后一个为 GitHub 官方源。清单附件携带 GitHub 提供的 SHA-256 摘要，系统
下载完成后应用自动重算比对，不一致即拒绝写入公共目录。用户选择源后可复制
链接、交给系统浏览器下载，或使用"系统下载"：先在系统选择器中选定保存位置
（取消则不发起下载），再由 `request.agent` 后台任务（`Mode.BACKGROUND`）
下载并经通知栏展示进度，校验通过后自动写入所选公共目录（平台限制"直写用户
文件仅允许前台任务"，故经应用缓存中转复制）；应用不代签名或安装 HAP。
