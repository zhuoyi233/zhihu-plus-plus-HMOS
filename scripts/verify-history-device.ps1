[CmdletBinding()]
param(
  [string]$Target = '127.0.0.1:5555',
  [string]$HdcPath = 'hdc',
  [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
  $PSNativeCommandUseErrorActionPreference = $false
}
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$output = Join-Path $repo '.tmp/history-parity'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$previous = Get-Location
try {
  Set-Location $repo
  $hdc = (Get-Command $HdcPath -ErrorAction Stop).Source
  $devices = & $hdc list targets 2>&1
  if ($LASTEXITCODE -ne 0 -or $devices -notcontains $Target) {
    throw "目标设备不在线：$Target"
  }
  if (-not $SkipBuild) {
    & devecocli build --modules entry@ohosTest 2>&1 |
      Tee-Object -FilePath (Join-Path $output 'build.log') | Out-Host
    if ($LASTEXITCODE -ne 0) { throw '设备测试 HAP 构建失败。' }
  }
  $testHap = Join-Path $repo 'entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap'
  $appHap = Join-Path $repo 'entry/build/default/outputs/default/entry-default-signed.hap'
  if (-not (Test-Path -LiteralPath $appHap -PathType Leaf)) {
    throw '请先运行 verify-harmony.ps1 -SkipDependencyInstall 完成主模块构建。'
  }
  if (-not (Test-Path -LiteralPath $testHap -PathType Leaf)) {
    throw "缺少签名设备测试包：$testHap"
  }
  $sources = @(
    'entry/src/ohosTest/ets/test/RemoteReadStoreDevice.test.ets',
    'entry/src/test/RemoteHistorySync.test.ets'
  )
  $expected = 0
  foreach ($source in $sources) {
    $expected += [regex]::Matches((Get-Content -LiteralPath $source -Raw), '(?m)^\s*it\s*\(').Count
  }
  & $hdc -t $Target install $appHap 2>&1 | Out-Host
  if ($LASTEXITCODE -ne 0) { throw '安装主模块 HAP 失败。' }
  & $hdc -t $Target install $testHap 2>&1 | Out-Host
  if ($LASTEXITCODE -ne 0) { throw '安装设备测试 HAP 失败。' }
  $report = Join-Path $output 'device-tests.log'
  & $hdc -t $Target shell aa test -b com.github.zhuoyi233.zhplus -m entry_test `
    -s unittest OpenHarmonyTestRunner -s timeout 120000 2>&1 |
    Tee-Object -FilePath $report | Out-Host
  if ($LASTEXITCODE -ne 0) { throw '设备测试命令执行失败。' }
  $result = Get-Content -LiteralPath $report -Raw
  $summaries = [regex]::Matches($result,
    'Tests run:\s*(\d+),\s*Failure:\s*(\d+),\s*Error:\s*(\d+),\s*Pass:\s*(\d+),\s*Ignore:\s*(\d+)')
  if ($summaries.Count -eq 0) { throw '缺少 Hypium 设备测试汇总，不能以命令退出码判定通过。' }
  $summary = $summaries[$summaries.Count - 1]
  if ([int]$summary.Groups[1].Value -ne $expected -or [int]$summary.Groups[4].Value -ne $expected -or
      [int]$summary.Groups[2].Value -ne 0 -or [int]$summary.Groups[3].Value -ne 0 -or
      [int]$summary.Groups[5].Value -ne 0) {
    throw "设备测试未全量通过（期望 $expected 项）：$($summary.Value)"
  }
  & devecocli log --device $Target --keyword rows=100000 --from 10m --tail 500 2>&1 |
    Tee-Object -FilePath (Join-Path $output 'device.log') | Out-Null
  if ($LASTEXITCODE -ne 0) { throw '设备测试日志读取失败。' }
  $benchmark = Get-Content -LiteralPath (Join-Path $output 'device.log') |
    Select-String -Pattern 'RemoteReadBenchmark.*rows=100000' | Select-Object -Last 1
  if ($null -eq $benchmark) { throw '设备测试缺少数据库查询基准记录。' }
  Write-Host $benchmark.Line
  Write-Host "服务器已读历史设备验收通过：$expected/$expected，报告：$report"
} finally {
  Set-Location $previous
}
