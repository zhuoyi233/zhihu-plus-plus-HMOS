[CmdletBinding()]
param(
  [string]$Repository = 'zhuoyi233/zhihu-plus-plus-HMOS',
  # 明确撤下损坏的历史版本，不能跳过最新正式版本的校验。
  [string[]]$ExcludeReleaseTag = @()
)

$ErrorActionPreference = 'Stop'
# gh 输出为 UTF-8；控制台默认编码可能是 GBK，中文 body 会被解码成乱码导致 JSON 解析失败。
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$projectRoot = Split-Path -Parent $PSScriptRoot
$catalogDirectory = Join-Path $projectRoot 'assets/update'
$bundledDirectory = Join-Path $projectRoot 'entry/src/main/resources/rawfile/update'

function Write-CatalogFiles {
  param([object[]]$Releases)
  New-Item -ItemType Directory -Force -Path $catalogDirectory | Out-Null
  New-Item -ItemType Directory -Force -Path $bundledDirectory | Out-Null
  ConvertTo-Json -InputObject $Releases -Depth 8 | Set-Content (Join-Path $catalogDirectory 'releases.json') -Encoding utf8
  $Releases[0] | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $catalogDirectory 'version.json') -Encoding utf8
  Copy-Item (Join-Path $catalogDirectory 'releases.json') (Join-Path $bundledDirectory 'releases.json') -Force
  Copy-Item (Join-Path $catalogDirectory 'version.json') (Join-Path $bundledDirectory 'version.json') -Force
}

# 仅发布的 HMOS Release 进入静态清单；草稿、预发布与继承的安卓 tag 均排除。
$response = @(gh api "repos/$Repository/releases?per_page=100" --paginate --jq '.[]')
if ($LASTEXITCODE -ne 0) {
  throw '无法获取已发布的 HMOS Release，未更新静态清单'
}
$published = @($response | ConvertFrom-Json |
  Where-Object { -not $_.draft -and -not $_.prerelease -and $_.tag_name -match '^HMOSv\d+(\.\d+)+$' } |
  Sort-Object { [version]($_.tag_name -replace '^HMOSv', '') } -Descending)
if ($published.Count -eq 0) {
  throw '无法获取已发布的 HMOS Release，未更新静态清单'
}
foreach ($tag in $ExcludeReleaseTag) {
  if ($tag -cnotin @($published.tag_name) -or $tag -ceq $published[0].tag_name) {
    throw "不能排除最新正式版本或不存在的历史 tag：$tag，未更新静态清单"
  }
  Write-Warning "显式排除历史版本 $tag：该版本将从在线与随包历史清单撤下，下次生成仍需明确指定此参数。"
}
$releases = @($published | Where-Object { $_.tag_name -cnotin $ExcludeReleaseTag } |
  ForEach-Object {
    $release = $_
    $version = $release.tag_name -replace '^HMOSv', ''
    $expectedName = "ZhihuPlusPlus-HMOS-v$version-unsigned.hap"
    $assets = @($release.assets | Where-Object { $_.name -cmatch '^ZhihuPlusPlus-HMOS-v.+-unsigned\.hap$' })
    if ($assets.Count -ne 1 -or $assets[0].name -cne $expectedName) {
      throw "$($release.tag_name) 必须包含唯一且版本一致的附件 $expectedName，未更新静态清单"
    }
    $asset = $assets[0]
    $expectedUrl = "https://github.com/$Repository/releases/download/$($release.tag_name)/$expectedName"
    if ($asset.browser_download_url -cne $expectedUrl) {
      throw "$($release.tag_name) 附件 URL 与仓库、tag 或文件名不一致，未更新静态清单"
    }
    $size = 0L
    if ([string]$asset.size -notmatch '^[1-9]\d*$' -or
        -not [long]::TryParse([string]$asset.size, [ref]$size)) {
      throw "$($release.tag_name) 附件大小必须是正整数，未更新静态清单"
    }
    if ([string]$asset.digest -cnotmatch '^sha256:[0-9a-fA-F]{64}$') {
      throw "$($release.tag_name) 附件缺少有效 SHA-256，未更新静态清单"
    }
    if ([string]::IsNullOrWhiteSpace($release.published_at)) {
      throw "$($release.tag_name) 缺少正式发布时间，未更新静态清单"
    }
    $digest = ([string]$asset.digest).Substring(7).ToLowerInvariant()
    $assets = @([ordered]@{
      name = $asset.name; browser_download_url = $asset.browser_download_url; size = $size; sha256 = $digest
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
if ($releases.Count -eq 0) {
  throw '无法获取已发布的 HMOS Release，未更新静态清单'
}
$releases = @($releases | Sort-Object { [version]($_.tag_name -replace '^HMOSv', '') } -Descending)
Write-CatalogFiles $releases
Write-Host "已更新 $($releases.Count) 个 Release；最新为 $($releases[0].tag_name)"
