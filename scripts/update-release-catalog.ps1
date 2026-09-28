param(
  [string]$Repository = 'zhuoyi233/zhihu-plus-plus-HMOS',
  # 预置模式：发布前把待发布版本的发布说明写入两份清单（无附件哈希），随 HAP 打包，
  # 供该版本“本版本更新内容”页在远端清单不可达时离线兜底。发布后再生成覆盖为真实元数据。
  [switch]$SeedPending,
  [string]$Version = '',
  [string]$NotesFile = ''
)

$ErrorActionPreference = 'Stop'
# gh 输出为 UTF-8；控制台默认编码可能是 GBK，中文 body 会被解码成乱码导致 JSON 解析失败。
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$projectRoot = Split-Path -Parent $PSScriptRoot
$catalogDirectory = Join-Path $projectRoot 'assets/update'
$bundledDirectory = Join-Path $projectRoot 'entry/src/main/resources/rawfile/update'
New-Item -ItemType Directory -Force -Path $catalogDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $bundledDirectory | Out-Null

function Write-CatalogFiles {
  param([object[]]$Releases)
  $Releases | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $catalogDirectory 'releases.json') -Encoding utf8
  $Releases[0] | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $catalogDirectory 'version.json') -Encoding utf8
  Copy-Item (Join-Path $catalogDirectory 'releases.json') (Join-Path $bundledDirectory 'releases.json') -Force
  Copy-Item (Join-Path $catalogDirectory 'version.json') (Join-Path $bundledDirectory 'version.json') -Force
}

if ($SeedPending) {
  if ($Version -notmatch '^\d+(\.\d+)+$') {
    throw '-SeedPending 需要 -Version 为数字版本号（如 0.6.0）'
  }
  if ([string]::IsNullOrWhiteSpace($NotesFile) -or -not (Test-Path $NotesFile)) {
    throw "-SeedPending 需要 -NotesFile 指向已写好的发布说明文稿（找不到：$NotesFile）"
  }
  $notesBody = (Get-Content $NotesFile -Raw -Encoding utf8).TrimEnd()
  if ([string]::IsNullOrWhiteSpace($notesBody)) {
    throw '发布说明文稿内容为空'
  }
  $pending = [pscustomobject][ordered]@{
    tag_name = "HMOSv$Version"
    name = "HMOSv$Version"
    html_url = "https://github.com/$Repository/releases/tag/HMOSv$Version"
    published_at = ''
    body = $notesBody
    assets = @()
  }
  $releasesPath = Join-Path $catalogDirectory 'releases.json'
  $existing = @()
  if (Test-Path $releasesPath) {
    $existing = @(Get-Content $releasesPath -Raw -Encoding utf8 | ConvertFrom-Json)
  }
  $merged = @($existing | Where-Object { $_.tag_name -ne $pending.tag_name }) + @($pending)
  $sorted = @($merged | Sort-Object { [version]($_.tag_name -replace '^HMOSv', '') } -Descending)
  Write-CatalogFiles $sorted
  Write-Host "已预置 $($pending.tag_name) 发布说明到仓库静态清单与 HAP 内置清单（无附件元数据）。"
  Write-Host '注意：Release 发布后必须运行本脚本再生成模式覆盖为真实附件元数据；推送远端前确保覆盖已完成，'
  Write-Host '否则线上清单会出现无附件可下载的待发布版本。'
  return
}

# 仅发布的 HMOS Release 进入静态清单；草稿、预发布与继承的安卓 tag 均排除。
$releases = @(gh api "repos/$Repository/releases?per_page=100" --paginate --jq '.[]' | ConvertFrom-Json |
  Where-Object { -not $_.draft -and -not $_.prerelease -and $_.tag_name -match '^HMOSv\d+(\.\d+)+$' } |
  ForEach-Object {
    $assets = @($_.assets | Where-Object { $_.name -match '^ZhihuPlusPlus-HMOS-v\d+(\.\d+)+-unsigned\.hap$' } |
      ForEach-Object {
        $digest = if ($_.digest) { ([string]$_.digest) -replace '^sha256:', '' } else { '' }
        [ordered]@{ name = $_.name; browser_download_url = $_.browser_download_url; size = $_.size; sha256 = $digest }
      })
    [ordered]@{
      tag_name = $_.tag_name
      name = $_.name
      html_url = $_.html_url
      published_at = $_.published_at
      body = $_.body
      assets = $assets
    }
  })
if ($LASTEXITCODE -ne 0 -or $releases.Count -eq 0) {
  throw '无法获取已发布的 HMOS Release，未更新静态清单'
}
$releases = @($releases | Sort-Object { [version]($_.tag_name -replace '^HMOSv', '') } -Descending)
Write-CatalogFiles $releases
Write-Host "已更新 $($releases.Count) 个 Release；最新为 $($releases[0].tag_name)"
