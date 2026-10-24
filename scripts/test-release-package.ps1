[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/release-package.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$testParent = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../.tmp/release-package-tests'))
$fixtureRoot = Join-Path $testParent ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $fixtureRoot | Out-Null
$passedCases = 0

try {
  foreach ($mapPath in @('', 'ets/sourceMaps.map', 'ets/symbolMap.map', 'ets/nested/other.map')) {
    foreach ($suffix in @('unsigned', 'signed')) {
      $hap = Join-Path $fixtureRoot "case-$passedCases-$suffix.hap"
      $zip = [IO.Compression.ZipFile]::Open($hap, [IO.Compression.ZipArchiveMode]::Create)
      try {
        $null = $zip.CreateEntry('ets/modules.abc')
        # rawfile 中普通 .map 文件不属于 ArkTS 调试映射。
        $null = $zip.CreateEntry('resources/rawfile/ordinary.map')
        if ($mapPath) { $null = $zip.CreateEntry($mapPath) }
      } finally { $zip.Dispose() }
      $rejected = $false
      try { Assert-HapNoSourceMap -HapPath $hap } catch {
        if ($_.Exception.Message -notmatch '发行 HAP 不应包含映射文件') { throw }
        $rejected = $true
      }
      if ($rejected -ne (-not [string]::IsNullOrEmpty($mapPath))) {
        throw "映射文件检查结果不正确：$mapPath / $suffix"
      }
      $passedCases++
      Write-Host "PASS $suffix / $(if ($mapPath) { $mapPath } else { '无映射' })"
    }
  }
  Write-Host "Release 包映射校验回归通过：$passedCases/$passedCases。"
} finally {
  $resolvedFixtureRoot = [IO.Path]::GetFullPath($fixtureRoot)
  if (-not $resolvedFixtureRoot.StartsWith($testParent + [IO.Path]::DirectorySeparatorChar,
      [StringComparison]::OrdinalIgnoreCase)) {
    throw '拒绝清理测试目录之外的路径'
  }
  Remove-Item -LiteralPath $resolvedFixtureRoot -Recurse -Force
}
