# 鸿蒙版静态更新清单

应用检查更新时优先读取 `assets/update/version.json`，发布说明读取
`assets/update/releases.json`。两者通过 GitHub Raw、jsDelivr 和 Fastly
三个入口并行获取，并使用 10 分钟进程内缓存。静态源未部署时，版本检查
回退到 GitHub Releases Atom；已打包的清单则提供当前版本的附件与发布说明。
运行时不请求 `api.github.com` 的 Release 接口。

每次正式 Release 发布后，维护者运行：

```powershell
pwsh -NoProfile -File scripts/update-release-catalog.ps1
```

脚本读取已发布的 `HMOSv*` Release，排除草稿、预发布和上游 Android tag，
并同时更新仓库静态清单与 HAP 内置清单。应核对最新版本、未签名 HAP 附件
与发布说明，再随下一次代码变更提交；远端 `main` 包含新清单后，旧版客户端
也能发现该版本。若清单尚未部署，Atom 可发现新版本，但下载源会等到附件
元数据可用时才展示。

页面的 18 个下载源由同一条真实未签名 HAP URL 生成：前 17 个为代理，
最后一个为 GitHub 官方源。清单附件携带 GitHub 提供的 SHA-256 摘要，系统
下载完成后应用自动重算比对，不一致即拒绝写入公共目录。用户选择源后可复制
链接、交给系统浏览器下载，或使用"系统下载"：先在系统选择器中选定保存位置
（取消则不发起下载），再由 `request.agent` 后台任务（`Mode.BACKGROUND`）
下载并经通知栏展示进度，校验通过后自动写入所选公共目录（平台限制"直写用户
文件仅允许前台任务"，故经应用缓存中转复制）；应用不代签名或安装 HAP。
