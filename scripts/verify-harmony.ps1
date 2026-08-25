[CmdletBinding()]
param(
  [string]$DevEcoHome = '',
  [string]$SdkRoot = '',
  [string]$NodePath = '',
  [string]$HvigorPath = '',
  [string]$OhpmPath = '',
  [string]$ExpectedCompileApiVersion = '26',
  [string]$ExpectedCompilePlatformVersion = '26.0.0',
  [string]$ExpectedTargetSdkVersion = '26.0.0',
  [string]$ExpectedCompatibleSdkVersion = '26.0.0',
  [string]$ExpectedBundleName = 'com.github.zhuoyi233.zhplus',
  [ValidateRange(0, 100000)]
  [int]$ExpectedTestCount = 0,
  [switch]$SkipDependencyInstall,
  [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
  $PSNativeCommandUseErrorActionPreference = $false
}

$script:Module = 'entry'
$script:Product = 'default'
$script:BuildMode = 'debug'
$script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Resolve-ExistingFile {
  param(
    [string]$ExplicitPath,
    [string[]]$Candidates,
    [string]$Description
  )

  $paths = @()
  if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
    $paths += $ExplicitPath
  }
  $paths += $Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  foreach ($candidate in $paths) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  throw "$Description 未找到。请通过脚本参数或 runner 环境变量显式配置。"
}

function Resolve-ExistingDirectory {
  param(
    [string]$ExplicitPath,
    [string[]]$Candidates,
    [string]$Description
  )

  $paths = @()
  if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
    $paths += $ExplicitPath
  }
  $paths += $Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  foreach ($candidate in $paths) {
    if (Test-Path -LiteralPath $candidate -PathType Container) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  throw "$Description 未找到。请通过脚本参数或 runner 环境变量显式配置。"
}

function Find-DevEcoHome {
  $candidates = @($env:HARMONY_DEVECO_HOME, $env:DEVECO_HOME, $env:DEVECO_STUDIO_HOME)
  $userProfile = [Environment]::GetFolderPath('UserProfile')
  $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
  $programFiles = [Environment]::GetFolderPath('ProgramFiles')
  if (-not [string]::IsNullOrWhiteSpace($userProfile)) {
    $candidates += (Join-Path $userProfile 'App\Huawei\DevEco Studio')
    $candidates += (Join-Path $userProfile 'App\DevEco Studio')
  }
  if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
    $candidates += (Join-Path $localAppData 'Huawei\DevEco Studio')
  }
  if (-not [string]::IsNullOrWhiteSpace($programFiles)) {
    $candidates += (Join-Path $programFiles 'Huawei\DevEco Studio')
  }

  if (-not [string]::IsNullOrWhiteSpace($SdkRoot)) {
    $sdkParent = Split-Path -Parent $SdkRoot
    if (Test-Path -LiteralPath (Join-Path $sdkParent 'tools') -PathType Container) {
      $candidates = @($sdkParent) + $candidates
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($env:HARMONY_SDK_ROOT)) {
    $sdkParent = Split-Path -Parent $env:HARMONY_SDK_ROOT
    if (Test-Path -LiteralPath (Join-Path $sdkParent 'tools') -PathType Container) {
      $candidates = @($sdkParent) + $candidates
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($env:DEVECO_SDK_HOME)) {
    $sdkParent = Split-Path -Parent $env:DEVECO_SDK_HOME
    if (Test-Path -LiteralPath (Join-Path $sdkParent 'tools') -PathType Container) {
      $candidates = @($sdkParent) + $candidates
    }
  }

  return Resolve-ExistingDirectory -ExplicitPath $DevEcoHome -Candidates $candidates -Description 'DevEco Studio 根目录'
}

function Invoke-NativeTool {
  param(
    [string]$Executable,
    [string[]]$Arguments,
    [string]$Description
  )

  Write-Host "==> $Description"
  $output = @(& $Executable @Arguments 2>&1)
  $exitCode = $LASTEXITCODE
  foreach ($line in $output) {
    Write-Host $line
  }
  if ($exitCode -ne 0) {
    throw "$Description 失败，退出码：$exitCode"
  }
  return [string]::Join([Environment]::NewLine, ($output | ForEach-Object { $_.ToString() }))
}

function Invoke-Hvigor {
  param(
    [string[]]$Arguments,
    [string]$Description,
    [string]$ResolvedNode,
    [string]$ResolvedHvigor
  )

  $output = Invoke-NativeTool -Executable $ResolvedNode -Arguments (@($ResolvedHvigor) + $Arguments) `
    -Description $Description
  if ($output -notmatch 'BUILD SUCCESSFUL') {
    throw "$Description 未输出 BUILD SUCCESSFUL，拒绝仅依赖退出码判定成功。"
  }
  if ($output -match 'BUILD FAILED|COMPILE RESULT\s*:\s*FAIL|ArkTS Compiler Error') {
    throw "$Description 输出包含失败标记。"
  }
  return $output
}

function Get-RegisteredTestCount {
  $suitePath = Join-Path $script:RepositoryRoot 'entry\src\test\List.test.ets'
  if (-not (Test-Path -LiteralPath $suitePath -PathType Leaf)) {
    throw "测试聚合入口不存在：$suitePath"
  }
  $suite = Get-Content -LiteralPath $suitePath -Raw
  $imports = @{}
  $importPattern = 'import\s+([A-Za-z_][A-Za-z0-9_]*)\s+from\s+[''"](\./[^''"]+\.test)[''"]\s*;'
  foreach ($match in [regex]::Matches($suite, $importPattern)) {
    $imports[$match.Groups[1].Value] = $match.Groups[2].Value
  }

  $registered = @()
  foreach ($match in [regex]::Matches($suite, '(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\(\);\s*$')) {
    $name = $match.Groups[1].Value
    if ($imports.ContainsKey($name)) {
      $registered += $name
    }
  }
  if ($registered.Count -eq 0) {
    throw 'List.test.ets 没有注册任何测试函数。'
  }

  $testCount = 0
  foreach ($name in $registered) {
    $relativePath = $imports[$name] + '.ets'
    $testPath = Join-Path (Split-Path -Parent $suitePath) $relativePath
    if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) {
      throw "已注册测试文件不存在：$testPath"
    }
    $testSource = Get-Content -LiteralPath $testPath -Raw
    $fileCount = [regex]::Matches($testSource, '(?m)^\s*it\s*\(').Count
    if ($fileCount -eq 0) {
      throw "已注册测试文件没有静态 it() 用例：$testPath"
    }
    $testCount += $fileCount
  }
  return $testCount
}

function Assert-HapApiVersions {
  param(
    [string]$HapPath,
    [int]$ExpectedTargetApiVersion,
    [int]$ExpectedCompatibleApiVersion,
    [string]$ExpectedBundleName
  )

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::OpenRead($HapPath)
  try {
    $packInfoEntry = $archive.Entries | Where-Object { $_.FullName -eq 'pack.info' } | Select-Object -First 1
    if ($null -eq $packInfoEntry) {
      throw "HAP 缺少 pack.info：$HapPath"
    }
    $reader = [System.IO.StreamReader]::new($packInfoEntry.Open())
    try {
      $packInfo = $reader.ReadToEnd() | ConvertFrom-Json
    } finally {
      $reader.Dispose()
    }
  } finally {
    $archive.Dispose()
  }

  $module = $packInfo.summary.modules | Select-Object -First 1
  if ($null -eq $module -or $null -eq $module.apiVersion) {
    throw "HAP pack.info 缺少模块 API 版本：$HapPath"
  }
  if ($module.apiVersion.target -ne $ExpectedTargetApiVersion -or
    $module.apiVersion.compatible -ne $ExpectedCompatibleApiVersion) {
    throw "HAP API 版本不匹配：target=$($module.apiVersion.target)，compatible=$($module.apiVersion.compatible)，期望 target=$ExpectedTargetApiVersion，compatible=$ExpectedCompatibleApiVersion。"
  }
  if ($packInfo.summary.app.bundleName -ne $ExpectedBundleName) {
    throw "HAP Bundle Name 不匹配：$($packInfo.summary.app.bundleName)，期望 $ExpectedBundleName。"
  }
  Write-Host "HAP API：target=$($module.apiVersion.target)，compatible=$($module.apiVersion.compatible)"
  Write-Host "HAP Bundle Name：$($packInfo.summary.app.bundleName)"
}

function Get-SdkApiVersion {
  param(
    [string]$SdkVersion,
    [string]$Description
  )
  if ($SdkVersion -match '\((\d+)\)$') {
    return [int]$Matches[1]
  }
  if ($SdkVersion -match '^(\d+)(?:\.\d+){0,2}$') {
    return [int]$Matches[1]
  }
  throw "$Description 必须为 SDK 版本，例如 26.0.0 或 6.1.1(24)：$SdkVersion"
}

$previousLocation = Get-Location
try {
  Set-Location $script:RepositoryRoot

  $resolvedDevEcoHome = Find-DevEcoHome
  $sdkCandidates = @(
    $env:HARMONY_SDK_ROOT,
    $env:DEVECO_SDK_HOME,
    (Join-Path $resolvedDevEcoHome 'sdk')
  )
  $resolvedSdkRoot = Resolve-ExistingDirectory -ExplicitPath $SdkRoot -Candidates $sdkCandidates `
    -Description 'HarmonyOS SDK 根目录'
  $sdkMetadataPath = Join-Path $resolvedSdkRoot 'default\sdk-pkg.json'
  if (-not (Test-Path -LiteralPath $sdkMetadataPath -PathType Leaf)) {
    throw "SDK 根目录必须包含 default\sdk-pkg.json，不能指向 sdk\default：$resolvedSdkRoot"
  }
  $sdkMetadata = Get-Content -LiteralPath $sdkMetadataPath -Raw | ConvertFrom-Json
  if ($sdkMetadata.data.apiVersion -ne $ExpectedCompileApiVersion -or
    $sdkMetadata.data.platformVersion -ne $ExpectedCompilePlatformVersion) {
    throw "编译 SDK 不匹配：实际为 $($sdkMetadata.data.platformVersion) API $($sdkMetadata.data.apiVersion)，期望为 $ExpectedCompilePlatformVersion API $ExpectedCompileApiVersion。"
  }

  $resolvedNode = Resolve-ExistingFile -ExplicitPath $NodePath `
    -Candidates @($env:HARMONY_NODE_PATH, (Join-Path $resolvedDevEcoHome 'tools\node\node.exe')) `
    -Description 'DevEco 内置 Node'
  $resolvedHvigor = Resolve-ExistingFile -ExplicitPath $HvigorPath `
    -Candidates @($env:HARMONY_HVIGOR_PATH, (Join-Path $resolvedDevEcoHome 'tools\hvigor\bin\hvigorw.js')) `
    -Description 'DevEco 内置 Hvigor'
  $resolvedOhpm = Resolve-ExistingFile -ExplicitPath $OhpmPath `
    -Candidates @($env:HARMONY_OHPM_PATH, (Join-Path $resolvedDevEcoHome 'tools\ohpm\bin\ohpm.bat')) `
    -Description 'DevEco 内置 ohpm'

  $buildProfile = Get-Content -LiteralPath (Join-Path $script:RepositoryRoot 'build-profile.json5') -Raw
  $targetPattern = '["'']?targetSdkVersion["'']?\s*:\s*["'']' + [regex]::Escape($ExpectedTargetSdkVersion) + '["'']'
  $compatiblePattern = '["'']?compatibleSdkVersion["'']?\s*:\s*["'']' + [regex]::Escape($ExpectedCompatibleSdkVersion) + '["'']'
  if ($buildProfile -notmatch $targetPattern -or $buildProfile -notmatch $compatiblePattern) {
    throw "build-profile.json5 必须固定 targetSdkVersion 为 $ExpectedTargetSdkVersion 且 compatibleSdkVersion 为 $ExpectedCompatibleSdkVersion。"
  }

  $env:DEVECO_SDK_HOME = $resolvedSdkRoot
  $nodeVersion = Invoke-NativeTool -Executable $resolvedNode -Arguments @('--version') -Description '检查 DevEco Node'
  Write-Host "DevEco: $resolvedDevEcoHome"
  Write-Host "编译 SDK: $resolvedSdkRoot ($($sdkMetadata.data.displayName), API $($sdkMetadata.data.apiVersion))"
  Write-Host "运行基线: target=$ExpectedTargetSdkVersion，compatible=$ExpectedCompatibleSdkVersion"
  Write-Host "Node: $resolvedNode ($nodeVersion)"
  Write-Host "Hvigor: $resolvedHvigor"

  $requiredDependencyPaths = @(
    (Join-Path $script:RepositoryRoot 'oh_modules\@ohos\hypium'),
    (Join-Path $script:RepositoryRoot 'entry\oh_modules\core'),
    (Join-Path $script:RepositoryRoot 'entry\oh_modules\data'),
    (Join-Path $script:RepositoryRoot 'entry\oh_modules\reader')
  )
  $missingDependencies = @($requiredDependencyPaths | Where-Object {
      -not (Test-Path -LiteralPath $_ -PathType Container)
    })
  if (-not $SkipDependencyInstall -and $missingDependencies.Count -gt 0) {
    Invoke-NativeTool -Executable $resolvedOhpm -Arguments @('install', '--all') `
      -Description '按 oh-package-lock.json5 安装 HarmonyOS 依赖' | Out-Null
  }
  $missingDependencies = @($requiredDependencyPaths | Where-Object {
      -not (Test-Path -LiteralPath $_ -PathType Container)
    })
  if ($missingDependencies.Count -gt 0) {
    throw "HarmonyOS 依赖未就绪：$($missingDependencies -join ', ')。请安装依赖，或不要使用 -SkipDependencyInstall。"
  }

  $commonProperties = @(
    '--mode', 'module',
    '-p', "module=$($script:Module)@$($script:Product)",
    '-p', "product=$($script:Product)",
    '-p', "buildMode=$($script:BuildMode)"
  )
  if (-not $SkipBuild) {
    Invoke-Hvigor -ResolvedNode $resolvedNode -ResolvedHvigor $resolvedHvigor `
      -Arguments (@('assembleHap') + $commonProperties + @('--no-daemon')) `
      -Description '构建 API 26 Debug HAP' | Out-Null
    $hapDirectory = Join-Path $script:RepositoryRoot "entry\build\$($script:Product)\outputs\$($script:Product)"
    $hap = Get-ChildItem -LiteralPath $hapDirectory -Filter '*.hap' -File -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($null -eq $hap) {
      throw "构建成功但没有在预期目录生成 HAP：$hapDirectory"
    }
    Write-Host "HAP: $($hap.FullName)"
    Assert-HapApiVersions -HapPath $hap.FullName `
      -ExpectedTargetApiVersion (Get-SdkApiVersion -SdkVersion $ExpectedTargetSdkVersion -Description 'targetSdkVersion') `
      -ExpectedCompatibleApiVersion (Get-SdkApiVersion -SdkVersion $ExpectedCompatibleSdkVersion -Description 'compatibleSdkVersion') `
      -ExpectedBundleName $ExpectedBundleName
  }

  $sourceTestCount = Get-RegisteredTestCount
  if ($ExpectedTestCount -gt 0 -and $ExpectedTestCount -ne $sourceTestCount) {
    throw "显式预期 $ExpectedTestCount 个测试，但 List.test.ets 当前注册 $sourceTestCount 个。"
  }
  $requiredTestCount = if ($ExpectedTestCount -gt 0) { $ExpectedTestCount } else { $sourceTestCount }
  Write-Host "期望 Hypium 用例数：$requiredTestCount"

  $testResultPath = Join-Path $script:RepositoryRoot `
    "entry\.test\$($script:Product)\intermediates\test\coverage_data\test_result.txt"
  if (Test-Path -LiteralPath $testResultPath -PathType Leaf) {
    Remove-Item -LiteralPath $testResultPath -Force
  }
  $testStartedAt = [DateTime]::UtcNow
  $testOutput = Invoke-Hvigor -ResolvedNode $resolvedNode -ResolvedHvigor $resolvedHvigor `
    -Arguments (@('test') + $commonProperties + @('--no-daemon')) `
    -Description '运行 ArkTS Hypium 测试'
  if ($testOutput -notmatch 'UnitTestArkTS' -or $testOutput -notmatch 'GenerateUnitTestResult') {
    throw 'Hvigor 输出缺少 UnitTestArkTS 或 GenerateUnitTestResult，测试链路不完整。'
  }
  if (-not (Test-Path -LiteralPath $testResultPath -PathType Leaf)) {
    throw "Hypium 没有生成 test_result.txt：$testResultPath"
  }
  $testResultFile = Get-Item -LiteralPath $testResultPath
  if ($testResultFile.LastWriteTimeUtc -lt $testStartedAt.AddSeconds(-2)) {
    throw 'Hypium 报告时间早于本次测试，拒绝读取陈旧结果。'
  }

  $testResult = Get-Content -LiteralPath $testResultPath -Raw
  $summaryPattern = 'Tests run:\s*(\d+),\s*Failure:\s*(\d+),\s*Error:\s*(\d+),\s*Pass:\s*(\d+),\s*Ignore:\s*(\d+)'
  $summaryMatches = [regex]::Matches($testResult, $summaryPattern)
  if ($summaryMatches.Count -ne 1) {
    throw 'Hypium 报告缺少唯一的 Tests run 汇总。'
  }
  $summary = $summaryMatches[0]
  $testsRun = [int]$summary.Groups[1].Value
  $failures = [int]$summary.Groups[2].Value
  $errors = [int]$summary.Groups[3].Value
  $passed = [int]$summary.Groups[4].Value
  $ignored = [int]$summary.Groups[5].Value
  $testEntries = [regex]::Matches($testResult, '(?m)^test=.+$').Count
  $resultEntries = [regex]::Matches($testResult, '(?m)^result=.+$').Count
  $successEntries = [regex]::Matches($testResult, '(?m)^result=Success\s*$').Count

  if ($testsRun -ne $requiredTestCount -or $testEntries -ne $requiredTestCount -or
    $resultEntries -ne $requiredTestCount) {
    throw "Hypium 用例数不一致：期望 $requiredTestCount，汇总 $testsRun，test 行 $testEntries，result 行 $resultEntries。"
  }
  if ($failures -ne 0 -or $errors -ne 0 -or $ignored -ne 0 -or
    $passed -ne $requiredTestCount -or $successEntries -ne $requiredTestCount) {
    throw "Hypium 未全量通过：Pass=$passed Failure=$failures Error=$errors Ignore=$ignored。"
  }

  Write-Host "HarmonyOS 迁移验证通过：API $ExpectedCompileApiVersion 编译，target=$ExpectedTargetSdkVersion，compatible=$ExpectedCompatibleSdkVersion，Hypium $passed/$requiredTestCount。"
  Write-Host "测试报告：$testResultPath"
} finally {
  Set-Location $previousLocation
}
