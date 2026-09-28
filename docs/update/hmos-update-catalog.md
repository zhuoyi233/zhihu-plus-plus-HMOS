# 鸿蒙版静态更新清单

应用检查更新时优先读取 `assets/update/version.json`，发布说明读取
`assets/update/releases.json`。两者先经 GitHub Raw 与 jsDelivr/Fastly 镜像
并行获取；4 秒内仍无有效响应，再叠加与「系统与更新」页共用的 17 个下载代理
（前缀拼接 raw 直连地址，含同样的 10 分钟防缓存参数）竞速，首个结构有效响应
获胜，并使用 10 分钟进程内缓存。不支持 raw 路径的代理返回的 HTML 错误页会被
结构校验计入失败，无需维护支持性白名单。静态源与代理全部不可用时，版本检查
回退到 GitHub Releases Atom；HAP 内置清单提供离线兜底（见下文预置条目）。
运行时不请求 `api.github.com` 的 Release 接口。

每个版本发布前（构建 HAP 之前），维护者写好发布说明文稿并运行：

```powershell
pwsh -NoProfile -File scripts/update-release-catalog.ps1 -SeedPending -Version x.y.z -NotesFile <文稿>
```

脚本把该版本的发布说明（无附件元数据，`published_at` 留空）置顶写入仓库
静态清单与 HAP 内置清单。发行 HAP 构建先于本版本 Release 发布，内置清单
天然无法携带本版本说明，预置条目即补上这一固有缺口：升级后首次启动的
"本版本更新内容"页与离线时的"已是最新版本"判定均由内置数据兜底。发布说明
文稿与 `gh release create --notes-file` 共用同一文件，保证应用内展示与
Release 页一致。

每次正式 Release 发布后，维护者运行：

```powershell
pwsh -NoProfile -File scripts/update-release-catalog.ps1
```

脚本读取已发布的 `HMOSv*` Release，排除草稿、预发布和上游 Android tag，
并用真实附件 URL/大小/SHA-256、发布时间覆盖预置占位条目，同时更新仓库
静态清单与 HAP 内置清单。应核对最新版本、未签名 HAP 附件与发布说明，再随
下一次代码变更提交；**推送远端前必须已完成覆盖**——预置条目无附件可下载，
若先于发布推上 `main`，旧版客户端会看到无法下载的"待发布版本"。远端 `main`
包含新清单后，旧版客户端也能发现该版本。若清单尚未部署，Atom 可发现新版本，
但下载源会等到附件元数据可用时才展示。

页面的 18 个下载源由同一条真实未签名 HAP URL 生成：前 17 个为代理，
最后一个为 GitHub 官方源。清单附件携带 GitHub 提供的 SHA-256 摘要，系统
下载完成后应用自动重算比对，不一致即拒绝写入公共目录。用户选择源后可复制
链接、交给系统浏览器下载，或使用"系统下载"：先在系统选择器中选定保存位置
（取消则不发起下载），再由 `request.agent` 后台任务（`Mode.BACKGROUND`）
下载并经通知栏展示进度，校验通过后自动写入所选公共目录（平台限制"直写用户
文件仅允许前台任务"，故经应用缓存中转复制）；应用不代签名或安装 HAP。
