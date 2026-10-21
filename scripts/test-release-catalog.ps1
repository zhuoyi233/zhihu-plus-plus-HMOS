[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$testParent = [IO.Path]::GetFullPath((Join-Path $repositoryRoot '.tmp/release-catalog-tests'))
$fixtureRoot = Join-Path $testParent ([guid]::NewGuid().ToString('N'))
$catalogPaths = @('assets/update/version.json', 'assets/update/releases.json',
  'entry/src/main/resources/rawfile/update/version.json', 'entry/src/main/resources/rawfile/update/releases.json')
$script:PassedCases = 0

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Test-Case {
  param([string]$Name, [scriptblock]$Action)
  & $Action
  $script:PassedCases++
  Write-Host "PASS $Name"
}

function New-Release {
  param([string]$Version = '0.6.0')
  return [pscustomobject]@{
    tag_name = "HMOSv$Version"; name = "HMOSv$Version"; draft = $false; prerelease = $false
    html_url = "https://github.com/fixture/fixture/releases/tag/HMOSv$Version"
    published_at = '2026-10-21T00:00:00Z'; body = '中文更新说明'
    assets = @([pscustomobject]@{
      name = "ZhihuPlusPlus-HMOS-v$Version-unsigned.hap"
      browser_download_url = "https://github.com/fixture/fixture/releases/download/HMOSv$Version/ZhihuPlusPlus-HMOS-v$Version-unsigned.hap"
      size = 12345; digest = 'sha256:' + ('AB' * 32)
    })
  }
}

function Invoke-Fixture {
  param([string[]]$ResponseText, [int]$ApiExitCode = 0,
    [string]$Repository = 'fixture/fixture', [string[]]$ExcludeReleaseTag = @())
  # 在隔离项目中执行实际脚本；本地函数替代 gh，不触发网络请求。
  function gh {
    $global:LASTEXITCODE = $ApiExitCode
    $ResponseText
  }
  & (Join-Path $fixtureRoot 'scripts/update-release-catalog.ps1') -Repository $Repository -ExcludeReleaseTag $ExcludeReleaseTag
}

function Get-CatalogHashes {
  return ($catalogPaths | ForEach-Object {
    (Get-FileHash -LiteralPath (Join-Path $fixtureRoot $_) -Algorithm SHA256).Hash
  }) -join ','
}

function Assert-Rejected {
  param([string[]]$ResponseText, [string]$Pattern, [int]$ApiExitCode = 0, [string[]]$ExcludeReleaseTag = @())
  $before = Get-CatalogHashes
  $rejected = $false
  try { Invoke-Fixture -ResponseText $ResponseText -ApiExitCode $ApiExitCode -ExcludeReleaseTag $ExcludeReleaseTag } catch {
    if ($_.Exception.Message -notmatch $Pattern) { throw }
    $rejected = $true
  }
  Assert-True $rejected "应拒绝输入：$Pattern"
  Assert-True ((Get-CatalogHashes) -eq $before) '失败后四份清单必须逐字节保持原样'
}

try {
  New-Item -ItemType Directory -Force -Path (Join-Path $fixtureRoot 'scripts') | Out-Null
  Copy-Item (Join-Path $PSScriptRoot 'update-release-catalog.ps1') (Join-Path $fixtureRoot 'scripts/update-release-catalog.ps1')
  foreach ($path in $catalogPaths) {
    $fullPath = Join-Path $fixtureRoot $path
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fullPath) | Out-Null
    Set-Content -LiteralPath $fullPath -Value "原清单 $path" -Encoding utf8
  }

  Test-Case '单版本输出数组，两处清单一致，SHA-256 规范化' {
    Invoke-Fixture (ConvertTo-Json -InputObject (New-Release) -Depth 8 -Compress)
    $history = Get-Content (Join-Path $fixtureRoot $catalogPaths[1]) -Raw | ConvertFrom-Json -NoEnumerate
    $latest = Get-Content (Join-Path $fixtureRoot $catalogPaths[0]) -Raw | ConvertFrom-Json -NoEnumerate
    Assert-True ($history -is [array] -and $history.Count -eq 1) '单版本历史必须为数组'
    Assert-True ($latest -isnot [array] -and $latest.tag_name -eq 'HMOSv0.6.0') '最新版必须为对象'
    Assert-True ($latest.assets[0].sha256 -ceq ('ab' * 32)) '摘要应规范化为小写'
    Assert-True ($latest.body -ceq '中文更新说明') '中文正文丢失'
    $hashes = (Get-CatalogHashes).Split(',')
    Assert-True ($hashes[0] -eq $hashes[2] -and $hashes[1] -eq $hashes[3]) '两处清单不一致'
  }

  Test-Case '多版本排序，排除草稿、预发布、安卓 tag 和非 HAP 附件' {
    $older = New-Release '0.5.9'
    $newer = New-Release '0.6.0'
    $newer.assets += [pscustomobject]@{ name = 'mapping.zip' }
    $draft = New-Release '0.7.0'; $draft.draft = $true; $draft.assets = @()
    $preview = New-Release '0.8.0'; $preview.prerelease = $true; $preview.assets = @()
    $android = New-Release '0.9.0'; $android.tag_name = '0.9.0'; $android.assets = @()
    $response = @($older, $draft, $android, $newer, $preview) | ForEach-Object { ConvertTo-Json $_ -Depth 8 -Compress }
    Invoke-Fixture $response
    $history = Get-Content (Join-Path $fixtureRoot $catalogPaths[1]) -Raw | ConvertFrom-Json -NoEnumerate
    Assert-True ($history.Count -eq 2 -and $history[0].tag_name -eq 'HMOSv0.6.0' -and
      $history[1].tag_name -eq 'HMOSv0.5.9' -and $history[0].assets.Count -eq 1) '过滤或排序错误'
  }

  $invalidCases = @(
    @{ Name = '无附件'; Change = { param($r) $r.assets = @() }; Pattern = '唯一且版本一致' },
    @{ Name = '错版本附件'; Change = { param($r) $r.assets[0].name = 'ZhihuPlusPlus-HMOS-v0.5.9-unsigned.hap' }; Pattern = '唯一且版本一致' },
    @{ Name = '重复发行附件'; Change = { param($r) $r.assets += $r.assets[0] }; Pattern = '唯一且版本一致' },
    @{ Name = '缺 URL'; Change = { param($r) $r.assets[0].browser_download_url = '' }; Pattern = 'URL' },
    @{ Name = '错版本 URL'; Change = { param($r) $r.assets[0].browser_download_url = $r.assets[0].browser_download_url.Replace('HMOSv0.6.0', 'HMOSv0.5.9') }; Pattern = 'URL' },
    @{ Name = '非官方 URL'; Change = { param($r) $r.assets[0].browser_download_url = 'https://example.test/file.hap' }; Pattern = 'URL' },
    @{ Name = '零大小'; Change = { param($r) $r.assets[0].size = 0 }; Pattern = '正整数' },
    @{ Name = '负大小'; Change = { param($r) $r.assets[0].size = -1 }; Pattern = '正整数' },
    @{ Name = '小数大小'; Change = { param($r) $r.assets[0].size = 1.5 }; Pattern = '正整数' },
    @{ Name = '缺大小'; Change = { param($r) $r.assets[0].PSObject.Properties.Remove('size') }; Pattern = '正整数' },
    @{ Name = '缺 digest'; Change = { param($r) $r.assets[0].PSObject.Properties.Remove('digest') }; Pattern = 'SHA-256' },
    @{ Name = '短摘要'; Change = { param($r) $r.assets[0].digest = 'sha256:ab' }; Pattern = 'SHA-256' },
    @{ Name = '非法摘要字符'; Change = { param($r) $r.assets[0].digest = 'sha256:' + ('z' * 64) }; Pattern = 'SHA-256' },
    @{ Name = '错误摘要算法'; Change = { param($r) $r.assets[0].digest = 'sha512:' + ('a' * 64) }; Pattern = 'SHA-256' },
    @{ Name = '无发布时间'; Change = { param($r) $r.published_at = '' }; Pattern = '正式发布时间' }
  )
  foreach ($case in $invalidCases) {
    Test-Case "拒绝$($case.Name)，保留原清单" {
      $release = New-Release
      & $case.Change $release
      Assert-Rejected (ConvertTo-Json $release -Depth 8 -Compress) $case.Pattern
    }
  }
  Test-Case '后续版本校验失败时不写入前面的有效版本' {
    $bad = New-Release '0.5.9'; $bad.assets = @()
    $response = @((New-Release), $bad) | ForEach-Object { ConvertTo-Json $_ -Depth 8 -Compress }
    Assert-Rejected $response '唯一且版本一致'
  }
  Test-Case 'API 非零退出且有部分数据时保留原清单' {
    Assert-Rejected (ConvertTo-Json (New-Release) -Depth 8 -Compress) '无法获取' 1
  }
  Test-Case '无正式版本时保留原清单' { Assert-Rejected @() '无法获取' }
  Test-Case '损坏的 API JSON 保留原清单' { Assert-Rejected '{broken' 'JSON' }
  Test-Case '允许显式排除损坏历史版本，仍生成有效最新版并告警' {
    $bad = New-Release '0.5.9'; $bad.assets = @()
    $response = @((New-Release), $bad) | ForEach-Object { ConvertTo-Json $_ -Depth 8 -Compress }
    $warnings = @()
    Invoke-Fixture -ResponseText $response -ExcludeReleaseTag 'HMOSv0.5.9' 3>&1 | ForEach-Object { $warnings += $_ }
    $history = Get-Content (Join-Path $fixtureRoot $catalogPaths[1]) -Raw | ConvertFrom-Json -NoEnumerate
    Assert-True ($history.Count -eq 1 -and $history[0].tag_name -eq 'HMOSv0.6.0') '排除无效'
    Assert-True (($warnings -join '') -match '显式排除历史版本') '缺少降级告警'
  }
  Test-Case '拒绝排除最新版或不存在的 tag，防止误跳过校验' {
    $response = ConvertTo-Json (New-Release) -Depth 8 -Compress
    Assert-Rejected -ResponseText $response -Pattern '不能排除' -ExcludeReleaseTag 'HMOSv0.6.0'
    Assert-Rejected -ResponseText $response -Pattern '不能排除' -ExcludeReleaseTag 'HMOSv0.1.0'
  }
  Test-Case '仓库现有正式清单的全部附件可通过新校验' {
    $existing = Get-Content (Join-Path $repositoryRoot 'assets/update/releases.json') -Raw | ConvertFrom-Json
    $response = @($existing | ForEach-Object {
      $_ | Add-Member draft $false
      $_ | Add-Member prerelease $false
      foreach ($asset in $_.assets) { $asset | Add-Member digest ('sha256:' + $asset.sha256) }
      ConvertTo-Json $_ -Depth 8 -Compress
    })
    Invoke-Fixture -ResponseText $response -Repository 'zhuoyi233/zhihu-plus-plus-HMOS'
    $history = Get-Content (Join-Path $fixtureRoot $catalogPaths[1]) -Raw | ConvertFrom-Json -NoEnumerate
    Assert-True ($history.Count -eq @($existing).Count) '历史版本丢失'
  }
  Write-Host "Release 清单脚本回归通过：$script:PassedCases/$script:PassedCases。"
} finally {
  $resolvedFixtureRoot = [IO.Path]::GetFullPath($fixtureRoot)
  if (-not $resolvedFixtureRoot.StartsWith($testParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw '拒绝清理测试目录之外的路径'
  }
  if (Test-Path -LiteralPath $resolvedFixtureRoot) {
    Remove-Item -LiteralPath $resolvedFixtureRoot -Recurse -Force
  }
}
