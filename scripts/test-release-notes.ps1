[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'lib/release-notes.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$testParent = [IO.Path]::GetFullPath((Join-Path $repositoryRoot '.tmp/release-notes-tests'))
$script:FixtureRoot = Join-Path $testParent ([guid]::NewGuid().ToString('N'))
$script:PassedCases = 0

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Assert-Rejected {
  param([scriptblock]$Action, [string]$Pattern)
  $rejected = $false
  try { & $Action } catch {
    if ($_.Exception.Message -notmatch $Pattern) { throw }
    $rejected = $true
  }
  Assert-True $rejected "应拒绝此输入：$Pattern"
}

function Test-Case {
  param([string]$Name, [scriptblock]$Action)
  & $Action
  $script:PassedCases++
  Write-Host "PASS $Name"
}

function New-Fixture {
  param([string]$Name)
  $root = Join-Path $script:FixtureRoot $Name
  foreach ($directory in @('assets/update', 'entry/src/main/resources/rawfile/update', 'docs/release-notes')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $root $directory) | Out-Null
  }
  $old = [pscustomobject]@{
    tag_name = 'HMOSv0.5.8'; name = 'HMOSv0.5.8'; html_url = 'https://example.test/0.5.8'
    published_at = '2026-10-10T00:00:00Z'; body = '旧版本说明'; assets = @(@{ name = 'old.hap'; sha256 = 'old-hash' })
  }
  foreach ($directory in @('assets/update', 'entry/src/main/resources/rawfile/update')) {
    ConvertTo-Json -InputObject $old -Depth 8 | Set-Content (Join-Path $root "$directory/version.json") -Encoding utf8
    ConvertTo-Json -InputObject @($old) -Depth 8 | Set-Content (Join-Path $root "$directory/releases.json") -Encoding utf8
  }
  [IO.File]::WriteAllText((Join-Path $root 'docs/release-notes/HMOSv0.5.9.md'),
    "# ZhihuPlusPlus-HMOS v0.5.9`r`n`r`n中文发布说明。`r`n`r`n- 完整正文`r`n", [Text.UTF8Encoding]::new($false))
  return $root
}

function Get-FixtureHashes {
  param([string]$Root)
  return @('assets/update/version.json', 'assets/update/releases.json',
    'entry/src/main/resources/rawfile/update/version.json', 'entry/src/main/resources/rawfile/update/releases.json') |
    ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $Root $_) -Algorithm SHA256).Hash }
}

function New-TestHap {
  param([string]$Path, [Object]$Latest, [Object[]]$Releases, [string]$Omit = '')
  $archive = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
  try {
    foreach ($name in @('version.json', 'releases.json')) {
      if ($name -eq $Omit) { continue }
      $entry = $archive.CreateEntry("resources/rawfile/update/$name")
      $writer = [IO.StreamWriter]::new($entry.Open(), [Text.UTF8Encoding]::new($false))
      try {
        $payload = if ($name -eq 'version.json') { $Latest } else { ,$Releases }
        $writer.Write((ConvertTo-Json -InputObject $payload -Depth 8))
      } finally { $writer.Dispose() }
    }
  } finally { $archive.Dispose() }
}

try {
  Test-Case '旧手动预置参数在执行前被拒绝' {
    Assert-Rejected { & (Join-Path $repositoryRoot 'scripts/update-release-catalog.ps1') -SeedPending } 'SeedPending'
  }
  Test-Case '首次发版自动注入，在线清单不变，成功后资源逐字节恢复' {
    $root = New-Fixture 'first-release'
    $before = @(Get-FixtureHashes $root)
    $notes = Get-ReleaseNotesBody $root '0.5.9'
    $hap = Join-Path $root 'valid.hap'
    Invoke-WithBundledReleaseNotes $root '0.5.9' $notes {
      $insideLatest = Get-Content (Join-Path $root 'entry/src/main/resources/rawfile/update/version.json') -Raw | ConvertFrom-Json
      $insideReleases = Get-Content (Join-Path $root 'entry/src/main/resources/rawfile/update/releases.json') -Raw | ConvertFrom-Json -NoEnumerate
      Assert-True ($insideReleases.Count -eq 2) '历史版本丢失'
      $during = @(Get-FixtureHashes $root)
      Assert-True ($during[0] -eq $before[0] -and $during[1] -eq $before[1]) '在线清单被构建改写'
      New-TestHap $hap $insideLatest $insideReleases
    }
    Assert-True ((@(Get-FixtureHashes $root) -join ',') -eq ($before -join ',')) '原始资源未恢复'
    Assert-HapReleaseNotes $hap '0.5.9' $notes
  }

  Test-Case '构建抛错后恢复资源，不改写在线清单' {
    $root = New-Fixture 'failed-build'
    $before = @(Get-FixtureHashes $root)
    $notes = Get-ReleaseNotesBody $root '0.5.9'
    Assert-Rejected { Invoke-WithBundledReleaseNotes $root '0.5.9' $notes { throw '模拟构建失败' } } '模拟构建失败'
    Assert-True ((@(Get-FixtureHashes $root) -join ',') -eq ($before -join ',')) '失败后资源未恢复'
  }

  Test-Case '正确恢复空文件和原本不存在的资源' {
    $root = New-Fixture 'empty-and-missing'
    $latestPath = Join-Path $root 'entry/src/main/resources/rawfile/update/version.json'
    $releasesPath = Join-Path $root 'entry/src/main/resources/rawfile/update/releases.json'
    [IO.File]::WriteAllBytes($latestPath, [byte[]]::new(0))
    Remove-Item -LiteralPath $releasesPath
    $notes = Get-ReleaseNotesBody $root '0.5.9'
    Assert-Rejected { Invoke-WithBundledReleaseNotes $root '0.5.9' $notes { throw '模拟中断' } } '模拟中断'
    Assert-True ((Test-Path -LiteralPath $latestPath) -and (Get-Item $latestPath).Length -eq 0) '空文件未保留'
    Assert-True (-not (Test-Path -LiteralPath $releasesPath)) '新增临时资源未移除'
  }

  Test-Case '重建已发布版本时清除自身旧哈希和发布时间' {
    $root = New-Fixture 'already-published'
    $old = @(Get-Content (Join-Path $root 'assets/update/releases.json') -Raw | ConvertFrom-Json)
    $publishedCurrent = [pscustomobject]@{
      tag_name = 'HMOSv0.5.9'; published_at = '2026-10-21T00:00:00Z'; body = '过期正文'
      assets = @(@{ name = 'old-current.hap'; sha256 = 'stale-self-hash' })
    }
    ConvertTo-Json -InputObject (@($publishedCurrent) + $old) -Depth 8 |
      Set-Content (Join-Path $root 'assets/update/releases.json') -Encoding utf8
    $before = @(Get-FixtureHashes $root)
    $notes = Get-ReleaseNotesBody $root '0.5.9'
    $hap = Join-Path $root 'rebuilt.hap'
    Invoke-WithBundledReleaseNotes $root '0.5.9' $notes {
      $latest = Get-Content (Join-Path $root 'entry/src/main/resources/rawfile/update/version.json') -Raw | ConvertFrom-Json
      $releases = @(Get-Content (Join-Path $root 'entry/src/main/resources/rawfile/update/releases.json') -Raw | ConvertFrom-Json)
      Assert-True ($releases.Count -eq 2) '当前版本未去重'
      New-TestHap $hap $latest $releases
    }
    Assert-HapReleaseNotes $hap '0.5.9' $notes
    Assert-True ((@(Get-FixtureHashes $root) -join ',') -eq ($before -join ',')) '已发布元数据未恢复'
  }

  Test-Case '拒绝在线清单中的未发布占位条目' {
    $root = New-Fixture 'pending-source'
    $pending = @{ tag_name = 'HMOSv0.5.9'; published_at = ''; body = '待发布'; assets = @() }
    ConvertTo-Json -InputObject @($pending) -Depth 8 | Set-Content (Join-Path $root 'assets/update/releases.json') -Encoding utf8
    $notes = Get-ReleaseNotesBody $root '0.5.9'
    $before = @(Get-FixtureHashes $root)
    Assert-Rejected { Invoke-WithBundledReleaseNotes $root '0.5.9' $notes { throw '不应进入构建' } } '在线清单含待发布'
    Assert-True ((@(Get-FixtureHashes $root) -join ',') -eq ($before -join ',')) '无效输入改写了资源'
  }

  $invalidNotesRoot = New-Fixture 'invalid-notes'
  $notesPath = Join-Path $invalidNotesRoot 'docs/release-notes/HMOSv0.5.9.md'
  Test-Case '拒绝版本不符的文稿标题' {
    Set-Content $notesPath "# ZhihuPlusPlus-HMOS v0.5.8`n正文" -Encoding utf8
    Assert-Rejected { Get-ReleaseNotesBody $invalidNotesRoot '0.5.9' } '发布说明必须'
  }
  Test-Case '拒绝没有正文的文稿' {
    Set-Content $notesPath '# ZhihuPlusPlus-HMOS v0.5.9' -Encoding utf8
    Assert-Rejected { Get-ReleaseNotesBody $invalidNotesRoot '0.5.9' } '发布说明必须'
  }
  Test-Case '拒绝缺失文稿' {
    Remove-Item -LiteralPath $notesPath
    Assert-Rejected { Get-ReleaseNotesBody $invalidNotesRoot '0.5.9' } '缺少发布说明文稿'
  }

  $archiveRoot = New-Fixture 'bad-packages'
  $expectedNotes = Get-ReleaseNotesBody $archiveRoot '0.5.9'
  $validCurrent = [pscustomobject]@{ tag_name = 'HMOSv0.5.9'; body = $expectedNotes; published_at = ''; assets = @() }
  Test-Case '拒绝只有旧版本清单的 HAP' {
    $old = Get-Content (Join-Path $archiveRoot 'assets/update/version.json') -Raw | ConvertFrom-Json
    $path = Join-Path $archiveRoot 'old.hap'
    New-TestHap $path $old @($old)
    Assert-Rejected { Assert-HapReleaseNotes $path '0.5.9' $expectedNotes } '缺少唯一的当前版本'
  }
  foreach ($catalogName in @('version.json', 'releases.json')) {
    Test-Case "拒绝缺少 $catalogName 的 HAP" {
      $path = Join-Path $archiveRoot "$catalogName-missing.hap"
      New-TestHap $path $validCurrent @($validCurrent) $catalogName
      Assert-Rejected { Assert-HapReleaseNotes $path '0.5.9' $expectedNotes } '缺少唯一的内置清单'
    }
    Test-Case "拒绝 $catalogName 中截断的正文" {
      $path = Join-Path $archiveRoot "$catalogName-truncated.hap"
      $truncated = [pscustomobject]@{ tag_name = 'HMOSv0.5.9'; body = '# ZhihuPlusPlus-HMOS v0.5.9'; published_at = ''; assets = @() }
      if ($catalogName -eq 'version.json') { New-TestHap $path $truncated @($validCurrent) }
      else { New-TestHap $path $validCurrent @($truncated) }
      Assert-Rejected { Assert-HapReleaseNotes $path '0.5.9' $expectedNotes } '内置说明与发布文稿不一致'
    }
  }
  Test-Case '拒绝重复的当前版本条目' {
    $path = Join-Path $archiveRoot 'duplicate.hap'
    New-TestHap $path $validCurrent @($validCurrent, $validCurrent)
    Assert-Rejected { Assert-HapReleaseNotes $path '0.5.9' $expectedNotes } '缺少唯一的当前版本'
  }
  Test-Case '拒绝内置当前包的旧附件哈希' {
    $path = Join-Path $archiveRoot 'stale-self-hash.hap'
    $stale = [pscustomobject]@{ tag_name = 'HMOSv0.5.9'; body = $expectedNotes; published_at = ''; assets = @(@{ sha256 = 'stale' }) }
    New-TestHap $path $stale @($stale)
    Assert-Rejected { Assert-HapReleaseNotes $path '0.5.9' $expectedNotes } '过期附件信息'
  }
  Test-Case '接受仅换行符不同的完整正文' {
    $path = Join-Path $archiveRoot 'crlf.hap'
    $crlf = [pscustomobject]@{ tag_name = 'HMOSv0.5.9'; body = $expectedNotes.Replace("`n", "`r`n") + "`r`n"; published_at = ''; assets = @() }
    New-TestHap $path $crlf @($crlf)
    Assert-HapReleaseNotes $path '0.5.9' $expectedNotes
  }
  Write-Host "Release 说明脚本回归通过：$script:PassedCases/$script:PassedCases。"
} finally {
  $resolvedFixtureRoot = [IO.Path]::GetFullPath($script:FixtureRoot)
  if (-not $resolvedFixtureRoot.StartsWith($testParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw '拒绝清理测试目录之外的路径'
  }
  if (Test-Path -LiteralPath $resolvedFixtureRoot) {
    Remove-Item -LiteralPath $resolvedFixtureRoot -Recurse -Force
  }
}
