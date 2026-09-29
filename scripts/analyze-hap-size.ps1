# HAP 包体积分析脚本（包体积优化计划阶段一，见 docs/package-size-optimization-plan.md）。
# 读取未签名 HAP（ZIP 结构）与包内 module.json / pack.info，输出分类体积报告（JSON）与控制台摘要；
# 支持 -CompareWith 与历史报告逐条目对比，定位造成体积变化的条目。
#
# 用法示例：
#   pwsh -NoProfile -File scripts/analyze-hap-size.ps1 `
#     -HapPath entry/build/default/outputs/default/entry-default-unsigned.hap `
#     -OutputPath entry/build/default/outputs/default/size-reports/<标签>.size-report.json `
#     [-TextReportPath <摘要.txt>] [-CompareWith <历史报告.json>]
#
# 比较口径：一律使用未签名 HAP 的实际字节数（压缩后条目大小），签名包仅用于设备验证。

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$HapPath,
  [string]$OutputPath = '',
  [string]$TextReportPath = '',
  [string]$CompareWith = '',
  [int]$TopLargest = 15,
  [string]$RepoRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
  $PSNativeCommandUseErrorActionPreference = $false
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

$categoryLegend = [ordered]@{
  'bytecode'           = 'ArkTS 字节码（ets/modules.abc）'
  'sourcemap'          = '源码映射（ets/sourceMaps.map）'
  'metadata'           = '包描述与资源索引（module.json、pack.info、pkgContextInfo.json、resources.index）'
  'rawfile-update'     = 'rawfile 内更新清单（resources/rawfile/update/）'
  'rawfile-diagnostics' = 'rawfile 内诊断资源（reader_probe.html、fixtures/）'
  'rawfile-other'      = 'rawfile 其他内容'
  'resources'          = 'resources 其余内容（media、profile 等）'
  'other'              = '未归类条目'
}

function Classify-HapEntry {
  param([string]$FullName)

  if ($FullName -eq 'ets/modules.abc') { return 'bytecode' }
  if ($FullName -eq 'ets/sourceMaps.map') { return 'sourcemap' }
  if ($FullName -in @('module.json', 'pack.info', 'pkgContextInfo.json', 'resources.index')) {
    return 'metadata'
  }
  if ($FullName -like 'resources/rawfile/update/*') { return 'rawfile-update' }
  if ($FullName -eq 'resources/rawfile/reader_probe.html' -or
      $FullName -like 'resources/rawfile/fixtures/*') { return 'rawfile-diagnostics' }
  if ($FullName -like 'resources/rawfile/*') { return 'rawfile-other' }
  if ($FullName -like 'resources/*') { return 'resources' }
  return 'other'
}

function Get-HapJsonEntry {
  param(
    [System.IO.Compression.ZipArchive]$Archive,
    [string]$EntryName
  )
  $entry = $Archive.Entries | Where-Object { $_.FullName -eq $EntryName } | Select-Object -First 1
  if ($null -eq $entry) {
    return $null
  }
  $reader = [System.IO.StreamReader]::new($entry.Open())
  try {
    return $reader.ReadToEnd() | ConvertFrom-Json
  } finally {
    $reader.Dispose()
  }
}

function Get-SourceState {
  param([string]$Root)

  $state = [ordered]@{
    repositoryRoot = $Root
    commit = $null
    branch = $null
    workingTreeDirty = $null
    trackedChangesPresent = $null
    dirtyEntries = @()
  }
  if (-not (Test-Path -LiteralPath (Join-Path $Root '.git'))) {
    return $state
  }
  try {
    $state.commit = (& git -C $Root 'rev-parse' 'HEAD' 2>$null | Select-Object -First 1)
    $branch = (& git -C $Root 'branch' '--show-current' 2>$null | Select-Object -First 1)
    if (-not [string]::IsNullOrWhiteSpace($branch)) { $state.branch = $branch }
    $porcelain = @(& git -C $Root 'status' '--porcelain' 2>$null)
    $state.workingTreeDirty = ($porcelain.Count -gt 0)
    # 已跟踪文件的实际改动才影响构建可复现性；未跟踪新增（文档/脚本）单独列出。
    $trackedChanges = @($porcelain | Where-Object { -not $_.StartsWith('??') })
    $state['trackedChangesPresent'] = ($trackedChanges.Count -gt 0)
    $state.dirtyEntries = @($porcelain | Select-Object -First 50)
  } catch {
    Write-Warning "读取 git 源码状态失败（忽略，不影响报告）：$($_.Exception.Message)"
  }
  return $state
}

function Get-ToolchainState {
  # 尽力采集工具链版本；采集不到的项记 null，不因环境差异中断报告。
  $state = [ordered]@{
    devEcoHome = $null
    sdk = $null
    node = $null
    nodeVersion = $null
    hvigor = $null
  }
  $candidates = @($env:HARMONY_DEVECO_HOME, $env:DEVECO_HOME, $env:DEVECO_STUDIO_HOME)
  $userProfile = [Environment]::GetFolderPath('UserProfile')
  $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
  if ($userProfile) {
    $candidates += (Join-Path $userProfile 'App\Huawei\DevEco Studio')
    $candidates += (Join-Path $userProfile 'App\DevEco Studio')
  }
  if ($localAppData) {
    $candidates += (Join-Path $localAppData 'Huawei\DevEco Studio')
  }
  $devEcoHome = $candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Select-Object -Unique | Where-Object { Test-Path -LiteralPath $_ -PathType Container } |
    Select-Object -First 1
  if ($null -eq $devEcoHome) {
    return $state
  }
  $state.devEcoHome = $devEcoHome

  $sdkPkgPath = Join-Path $devEcoHome 'sdk\default\sdk-pkg.json'
  if (Test-Path -LiteralPath $sdkPkgPath -PathType Leaf) {
    try {
      $sdkPkg = Get-Content -LiteralPath $sdkPkgPath -Raw | ConvertFrom-Json
      $state.sdk = [ordered]@{
        displayName = $sdkPkg.data.displayName
        apiVersion = $sdkPkg.data.apiVersion
        platformVersion = $sdkPkg.data.platformVersion
      }
    } catch {
      Write-Warning "解析 sdk-pkg.json 失败（忽略）：$($_.Exception.Message)"
    }
  }
  $nodePath = Join-Path $devEcoHome 'tools\node\node.exe'
  if (Test-Path -LiteralPath $nodePath -PathType Leaf) {
    $state.node = $nodePath
    try {
      $state.nodeVersion = (& $nodePath '--version' 2>$null | Select-Object -First 1)
    } catch {
      Write-Warning "获取 Node 版本失败（忽略）：$($_.Exception.Message)"
    }
  }
  $hvigorPath = Join-Path $devEcoHome 'tools\hvigor\bin\hvigorw.js'
  if (Test-Path -LiteralPath $hvigorPath -PathType Leaf) {
    $state.hvigor = $hvigorPath
  }
  return $state
}

function Get-PropertySum {
  # 空集合的 Measure-Object 不输出对象，StrictMode 下直接取 .Sum 会报错；此处统一兜底为 0。
  param([object[]]$Items, [string]$Property)

  if ($null -eq $Items -or $Items.Count -eq 0) {
    return [long]0
  }
  $sum = ($Items | Measure-Object -Property $Property -Sum).Sum
  if ($null -eq $sum) {
    return [long]0
  }
  return [long]$sum
}

function Format-Bytes {
  param([long]$Bytes)
  if ([Math]::Abs($Bytes) -ge 1MB) {
    return ('{0:N0} B ({1:N2} MiB)' -f $Bytes, ($Bytes / 1MB))
  }
  return ('{0:N0} B ({1:N1} KiB)' -f $Bytes, ($Bytes / 1KB))
}

# ---- 主流程 ----

$resolvedHap = (Resolve-Path -LiteralPath $HapPath -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath $resolvedHap -PathType Leaf)) {
  throw "HAP 不存在：$resolvedHap"
}
if ([System.IO.Path]::GetExtension($resolvedHap) -ne '.hap') {
  throw "只接受 .hap 产物（比较口径为未签名 HAP）：$resolvedHap"
}
$hapItem = Get-Item -LiteralPath $resolvedHap
$archive = [System.IO.Compression.ZipFile]::OpenRead($resolvedHap)

$summaryLines = [System.Collections.Generic.List[string]]::new()
try {
  $entries = foreach ($entry in $archive.Entries) {
    $compressed = [long]$entry.CompressedLength
    $raw = [long]$entry.Length
    [pscustomobject]@{
      fullName = $entry.FullName
      compressedBytes = $compressed
      rawBytes = $raw
      stored = ($compressed -eq $raw)
      category = Classify-HapEntry -FullName $entry.FullName
    }
  }

  $fileLength = [long]$hapItem.Length
  $compressedTotal = Get-PropertySum -Items $entries -Property 'compressedBytes'
  $rawTotal = Get-PropertySum -Items $entries -Property 'rawBytes'
  $zipOverhead = $fileLength - $compressedTotal
  if ($zipOverhead -lt 0) {
    throw "ZIP 开销计算为负（$zipOverhead），HAP 文件可能损坏或不完整：$resolvedHap"
  }

  $categories = foreach ($category in $categoryLegend.Keys) {
    $scoped = @($entries | Where-Object { $_.category -eq $category })
    [pscustomobject]@{
      category = $category
      description = $categoryLegend[$category]
      entryCount = $scoped.Count
      compressedBytes = (Get-PropertySum -Items $scoped -Property 'compressedBytes')
      rawBytes = (Get-PropertySum -Items $scoped -Property 'rawBytes')
    }
  }
  $categorizedSum = Get-PropertySum -Items $categories -Property 'compressedBytes'
  if ($categorizedSum + $zipOverhead -ne $fileLength) {
    throw ('分项统计与文件总字节数不符：{0} + {1} != {2}' -f $categorizedSum, $zipOverhead, $fileLength)
  }

  $moduleJson = Get-HapJsonEntry -Archive $archive -EntryName 'module.json'
  $packInfo = Get-HapJsonEntry -Archive $archive -EntryName 'pack.info'
  if ($null -eq $moduleJson) { throw "HAP 缺少 module.json：$resolvedHap" }
  if ($null -eq $packInfo) { throw "HAP 缺少 pack.info：$resolvedHap" }

  $packageMeta = [ordered]@{
    bundleName = $moduleJson.app.bundleName
    versionName = $moduleJson.app.versionName
    versionCode = $moduleJson.app.versionCode
    buildMode = $moduleJson.app.buildMode
    debug = $moduleJson.app.debug
    compileSdkVersion = $moduleJson.app.compileSdkVersion
    minAPIVersion = $moduleJson.app.minAPIVersion
    targetAPIVersion = $moduleJson.app.targetAPIVersion
    virtualMachine = $moduleJson.module.virtualMachine
    compatibleApiVersion = $packInfo.summary.modules[0].apiVersion.compatible
    targetApiVersionPack = $packInfo.summary.modules[0].apiVersion.target
    moduleName = $packInfo.summary.modules[0].distro.moduleName
  }
} finally {
  $archive.Dispose()
}

$sha256 = (Get-FileHash -LiteralPath $resolvedHap -Algorithm SHA256).Hash.ToLowerInvariant()

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}
$sourceState = Get-SourceState -Root $RepoRoot
$toolchainState = Get-ToolchainState

$largest = @($entries | Sort-Object compressedBytes -Descending | Select-Object -First $TopLargest)

$report = [pscustomobject]@{
  schema = 'hap-size-report/1'
  generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
  hap = [ordered]@{
    path = $resolvedHap
    fileName = $hapItem.Name
    fileLengthBytes = $fileLength
    sha256 = $sha256
    lastWriteTimeUtc = $hapItem.LastWriteTimeUtc.ToString('o')
    entryCount = $entries.Count
    storedEntries = @($entries | Where-Object { $_.stored }).Count
    compressedEntryBytes = $compressedTotal
    rawEntryBytes = $rawTotal
    zipOverheadBytes = $zipOverhead
  }
  packageMeta = $packageMeta
  sourceState = $sourceState
  toolchain = $toolchainState
  categories = $categories
  categoryLegend = $categoryLegend
  largestEntries = $largest
  entries = $entries
}

# ---- 对比 ----

$hasCompare = $false
if (-not [string]::IsNullOrWhiteSpace($CompareWith)) {
  $previousResolved = (Resolve-Path -LiteralPath $CompareWith -ErrorAction Stop).Path
  $previous = Get-Content -LiteralPath $previousResolved -Raw | ConvertFrom-Json
  if ($previous.schema -ne 'hap-size-report/1') {
    throw "历史报告 schema 不是 hap-size-report/1：$previousResolved"
  }
  $previousEntries = @{}
  foreach ($entry in $previous.entries) {
    $previousEntries[$entry.fullName] = [long]$entry.compressedBytes
  }
  $currentEntries = @{}
  foreach ($entry in $entries) {
    $currentEntries[$entry.fullName] = [long]$entry.compressedBytes
  }

  $changed = foreach ($name in ($previousEntries.Keys | Where-Object { $currentEntries.ContainsKey($_) })) {
    $delta = [long]$currentEntries[$name] - [long]$previousEntries[$name]
    if ($delta -ne 0) {
      [pscustomobject]@{
        fullName = $name
        previousBytes = [long]$previousEntries[$name]
        currentBytes = [long]$currentEntries[$name]
        deltaBytes = $delta
      }
    }
  }
  $changed = @($changed | Sort-Object deltaBytes)
  $added = @($currentEntries.Keys | Where-Object { -not $previousEntries.ContainsKey($_) } |
    ForEach-Object { [pscustomobject]@{ fullName = $_; currentBytes = [long]$currentEntries[$_] } } |
    Sort-Object currentBytes -Descending)
  $removed = @($previousEntries.Keys | Where-Object { -not $currentEntries.ContainsKey($_) } |
    ForEach-Object { [pscustomobject]@{ fullName = $_; previousBytes = [long]$previousEntries[$_] } } |
    Sort-Object previousBytes -Descending)

  $categoryDeltas = foreach ($category in $categoryLegend.Keys) {
    $previousBytes = [long]($previous.categories | Where-Object { $_.category -eq $category } |
      ForEach-Object { $_.compressedBytes } | Select-Object -First 1)
    if ($null -eq $previousBytes) { $previousBytes = 0 }
    $currentBytes = [long](($categories | Where-Object { $_.category -eq $category }).compressedBytes)
    [pscustomobject]@{
      category = $category
      previousBytes = $previousBytes
      currentBytes = $currentBytes
      deltaBytes = ($currentBytes - $previousBytes)
    }
  }

  $totalDelta = [long]$fileLength - [long]$previous.hap.fileLengthBytes
  $report | Add-Member -NotePropertyName 'compare' -NotePropertyValue ([pscustomobject]@{
    comparedWith = $previousResolved
    previousGeneratedAtUtc = $previous.generatedAtUtc
    previousFileLengthBytes = [long]$previous.hap.fileLengthBytes
    previousSha256 = $previous.hap.sha256
    totalDeltaBytes = $totalDelta
    zipOverheadDeltaBytes = ([long]$zipOverhead - [long]$previous.hap.zipOverheadBytes)
    categories = @($categoryDeltas)
    changedEntries = $changed
    addedEntries = $added
    removedEntries = $removed
  })
  $hasCompare = $true
}

# ---- 输出 ----

$summaryLines.Add("=== HAP 体积报告：$($hapItem.Name) ===")
$summaryLines.Add(('文件大小：{0}' -f (Format-Bytes $fileLength)))
$summaryLines.Add(('SHA-256：{0}' -f $sha256))
$summaryLines.Add(('条目数：{0}（其中 Stored 存储 {1} 个）；条目压缩后合计 {2}；ZIP 开销 {3}' -f `
    $entries.Count, @($entries | Where-Object { $_.stored }).Count, (Format-Bytes $compressedTotal), (Format-Bytes $zipOverhead)))
$summaryLines.Add('')
$summaryLines.Add('包内元数据（module.json / pack.info）：')
$summaryLines.Add(('  bundleName={0}  version={1}(code {2})  buildMode={3}  debug={4}' -f `
    $packageMeta.bundleName, $packageMeta.versionName, $packageMeta.versionCode, $packageMeta.buildMode, $packageMeta.debug))
$summaryLines.Add(('  compileSdkVersion={0}  minAPIVersion={1}  targetAPIVersion={2}  virtualMachine={3}' -f `
    $packageMeta.compileSdkVersion, $packageMeta.minAPIVersion, $packageMeta.targetAPIVersion, $packageMeta.virtualMachine))
$summaryLines.Add('')
$summaryLines.Add('源码状态：')
$summaryLines.Add(('  仓库：{0}' -f $sourceState.repositoryRoot))
$summaryLines.Add(('  commit：{0}  分支：{1}  工作区有改动：{2}' -f `
    $(if ($sourceState.commit) { $sourceState.commit } else { '<未知>' }),
    $(if ($sourceState.branch) { $sourceState.branch } else { '<未知>' }),
    $(if ($null -ne $sourceState.workingTreeDirty) { $sourceState.workingTreeDirty } else { '<未知>' })))
$summaryLines.Add(('  已跟踪源码有改动：{0}（未跟踪新增 {1} 项，详见 JSON dirtyEntries）' -f `
    $(if ($null -ne $sourceState.trackedChangesPresent) { $sourceState.trackedChangesPresent } else { '<未知>' }),
    $sourceState.dirtyEntries.Count))
$summaryLines.Add('')
$summaryLines.Add('工具链：')
$summaryLines.Add(('  DevEco：{0}' -f $(if ($toolchainState.devEcoHome) { $toolchainState.devEcoHome } else { '<未找到，跳过采集>' })))
if ($toolchainState.devEcoHome) {
  $summaryLines.Add(('  SDK：{0}（API {1}，platform {2}）' -f `
      $toolchainState.sdk.displayName, $toolchainState.sdk.apiVersion, $toolchainState.sdk.platformVersion))
  $summaryLines.Add(('  Node：{0}' -f $(if ($toolchainState.nodeVersion) { $toolchainState.nodeVersion } else { '<未知>' })))
  $summaryLines.Add(('  Hvigor：{0}' -f $(if ($toolchainState.hvigor) { $toolchainState.hvigor } else { '<未找到>' })))
}
$summaryLines.Add('')
$summaryLines.Add('分类体积（压缩后字节数，占文件总大小比例）：')
foreach ($category in $categories) {
  $share = if ($fileLength -gt 0) { [Math]::Round(100.0 * $category.compressedBytes / $fileLength, 1) } else { 0 }
  $summaryLines.Add(('  {0,-20} {1,12:N0}  {2,5}%  {3} 个条目  — {4}' -f `
      $category.category, $category.compressedBytes, $share, $category.entryCount, $category.description))
}
$summaryLines.Add(('  {0,-20} {1,12:N0}  {2,5}%  （本地文件头 + 中央目录等）' -f `
    'zip-overhead', $zipOverhead, $(if ($fileLength -gt 0) { [Math]::Round(100.0 * $zipOverhead / $fileLength, 1) } else { 0 })))
$summaryLines.Add(('  校验：分项合计 {0:N0} + ZIP 开销 {1:N0} = {2:N0} = 文件总字节数' -f $categorizedSum, $zipOverhead, $fileLength))
$summaryLines.Add('')
$summaryLines.Add(('最大条目（Top {0}，按压缩后字节）：' -f $TopLargest))
foreach ($entry in $largest) {
  $summaryLines.Add(('  {0,12:N0}  {1}' -f $entry.compressedBytes, $entry.fullName))
}

if ($hasCompare) {
  $c = $report.compare
  $summaryLines.Add('')
  $summaryLines.Add('=== 与历史报告对比 ===')
  $summaryLines.Add(('对比对象：{0}（{1}，SHA-256 {2}）' -f $c.comparedWith, $c.previousGeneratedAtUtc, $c.previousSha256))
  $summaryLines.Add(('总大小：{0:N0} → {1:N0}，变化 {2:+#,0;-#,0;0} 字节（{3:+0.0;-0.0;0.0}%）' -f `
      $c.previousFileLengthBytes, $fileLength, $c.totalDeltaBytes,
      $(if ($c.previousFileLengthBytes -gt 0) { [Math]::Round(100.0 * $c.totalDeltaBytes / $c.previousFileLengthBytes, 2) } else { 0 })))
  $summaryLines.Add(('ZIP 开销变化：{0:+#,0;-#,0;0} 字节' -f $c.zipOverheadDeltaBytes))
  $summaryLines.Add('')
  $summaryLines.Add('分类变化：')
  foreach ($category in $c.categories) {
    if ($category.previousBytes -ne $category.currentBytes -or $category.deltaBytes -ne 0) {
      $summaryLines.Add(('  {0,-20} {1,12:N0} → {2,12:N0}  变化 {3:+#,0;-#,0;0}' -f `
          $category.category, $category.previousBytes, $category.currentBytes, $category.deltaBytes))
    }
  }
  $summaryLines.Add('')
  $summaryLines.Add(('条目级变化（{0} 个变化，{1} 个新增，{2} 个移除）：' -f $c.changedEntries.Count, $c.addedEntries.Count, $c.removedEntries.Count))
  foreach ($entry in $c.changedEntries) {
    $summaryLines.Add(('  {0:+#,0;-#,0;0}  {1}  ({2:N0} → {3:N0})' -f $entry.deltaBytes, $entry.fullName, $entry.previousBytes, $entry.currentBytes))
  }
  foreach ($entry in $c.addedEntries) {
    $summaryLines.Add(('  +{0,12:N0}  {1}  (新增)' -f $entry.currentBytes, $entry.fullName))
  }
  foreach ($entry in $c.removedEntries) {
    $summaryLines.Add(('  -{0,12:N0}  {1}  (移除)' -f $entry.previousBytes, $entry.fullName))
  }
  if ($c.changedEntries.Count -eq 0 -and $c.addedEntries.Count -eq 0 -and $c.removedEntries.Count -eq 0) {
    $summaryLines.Add('  （无条目级差异）')
  }
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path (Split-Path -Parent $resolvedHap) ($hapItem.Name + '.size-report.json')
}
$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
  New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($OutputPath, ($report | ConvertTo-Json -Depth 8), $utf8NoBom)

$summaryLines.Add('')
$summaryLines.Add("JSON 报告：$OutputPath")

foreach ($line in $summaryLines) {
  Write-Host $line
}
if (-not [string]::IsNullOrWhiteSpace($TextReportPath)) {
  $textDirectory = Split-Path -Parent $TextReportPath
  if (-not (Test-Path -LiteralPath $textDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $textDirectory -Force | Out-Null
  }
  [System.IO.File]::WriteAllText($TextReportPath, (($summaryLines -join [Environment]::NewLine) + [Environment]::NewLine), $utf8NoBom)
  Write-Host "文本摘要：$TextReportPath"
}
