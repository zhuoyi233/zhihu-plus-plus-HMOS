param(
  [string]$Repository = 'zhuoyi233/zhihu-plus-plus-HMOS'
)

$ErrorActionPreference = 'Stop'
# gh 输出为 UTF-8；控制台默认编码可能是 GBK，中文 body 会被解码成乱码导致 JSON 解析失败。
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$projectRoot = Split-Path -Parent $PSScriptRoot
$catalogDirectory = Join-Path $projectRoot 'assets/update'
New-Item -ItemType Directory -Force -Path $catalogDirectory | Out-Null

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
$releases | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $catalogDirectory 'releases.json') -Encoding utf8
$releases[0] | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $catalogDirectory 'version.json') -Encoding utf8
$bundledDirectory = Join-Path $projectRoot 'entry/src/main/resources/rawfile/update'
New-Item -ItemType Directory -Force -Path $bundledDirectory | Out-Null
Copy-Item (Join-Path $catalogDirectory 'releases.json') (Join-Path $bundledDirectory 'releases.json') -Force
Copy-Item (Join-Path $catalogDirectory 'version.json') (Join-Path $bundledDirectory 'version.json') -Force
Write-Host "已更新 $($releases.Count) 个 Release；最新为 $($releases[0].tag_name)"
