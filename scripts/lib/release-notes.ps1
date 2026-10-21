# Release 构建专用：从随源码提交的文稿生成内置资源，不修改在线更新清单。
function ConvertTo-NormalizedReleaseNotes {
  param([string]$Body)
  return $Body.Replace("`r`n", "`n").Replace("`r", "`n").TrimEnd()
}

function Get-ReleaseNotesBody {
  param([string]$RepositoryRoot, [string]$VersionName)

  if ($VersionName -notmatch '^\d+\.\d+\.\d+$') {
    throw "无效的发行版本号：$VersionName"
  }
  $notesPath = Join-Path $RepositoryRoot "docs/release-notes/HMOSv$VersionName.md"
  if (-not (Test-Path -LiteralPath $notesPath -PathType Leaf)) {
    throw "Release 构建缺少发布说明文稿：$notesPath。请先将文稿随版本号提交。"
  }
  $body = ConvertTo-NormalizedReleaseNotes (Get-Content -LiteralPath $notesPath -Raw -Encoding utf8)
  $heading = "# ZhihuPlusPlus-HMOS v$VersionName"
  if ($body.Split("`n")[0] -cne $heading -or $body.Length -le $heading.Length) {
    throw "发布说明必须以 $heading 开头并包含正文：$notesPath"
  }
  return $body
}

function Invoke-WithBundledReleaseNotes {
  param(
    [string]$RepositoryRoot,
    [string]$VersionName,
    [string]$NotesBody,
    [scriptblock]$BuildAction
  )

  $sourcePath = Join-Path $RepositoryRoot 'assets/update/releases.json'
  $published = Get-Content -LiteralPath $sourcePath -Raw -Encoding utf8 | ConvertFrom-Json -NoEnumerate
  if ($published -isnot [array]) {
    throw "已发布清单必须是 JSON 数组：$sourcePath"
  }
  foreach ($release in $published) {
    if ([string]::IsNullOrWhiteSpace($release.published_at) -or @($release.assets).Count -eq 0) {
      throw "在线清单含待发布占位条目：$($release.tag_name)。请先恢复已发布清单。"
    }
  }
  # 当前包不能内置自身的哈希；重建已发布版本时也必须移除旧附件元数据。
  $current = [pscustomobject][ordered]@{
    tag_name = "HMOSv$VersionName"
    name = "HMOSv$VersionName"
    html_url = "https://github.com/zhuoyi233/zhihu-plus-plus-HMOS/releases/tag/HMOSv$VersionName"
    published_at = ''
    body = $NotesBody
    assets = @()
  }
  $releases = @($current) + @($published | Where-Object { $_.tag_name -ne $current.tag_name })
  $bundledDirectory = Join-Path $RepositoryRoot 'entry/src/main/resources/rawfile/update'
  $payloads = @{
    'version.json' = ConvertTo-Json -InputObject $current -Depth 8
    'releases.json' = ConvertTo-Json -InputObject $releases -Depth 8
  }
  $snapshots = @()
  foreach ($name in @('version.json', 'releases.json')) {
    $path = Join-Path $bundledDirectory $name
    $snapshots += [pscustomobject]@{
      Path = $path
      Bytes = if (Test-Path -LiteralPath $path -PathType Leaf) { ,([IO.File]::ReadAllBytes($path)) } else { $null }
      Payload = $payloads[$name]
    }
  }
  try {
    New-Item -ItemType Directory -Force -Path $bundledDirectory | Out-Null
    foreach ($snapshot in $snapshots) {
      [IO.File]::WriteAllText($snapshot.Path, $snapshot.Payload, [Text.UTF8Encoding]::new($false))
    }
    Write-Host "Release 构建已自动注入 HMOSv$VersionName 内置说明，在线清单保持不变。"
    & $BuildAction
  } finally {
    foreach ($snapshot in $snapshots) {
      if ($null -eq $snapshot.Bytes) {
        if (Test-Path -LiteralPath $snapshot.Path -PathType Leaf) {
          Remove-Item -LiteralPath $snapshot.Path -Force
        }
      } else {
        [IO.File]::WriteAllBytes($snapshot.Path, $snapshot.Bytes)
      }
    }
    Write-Host 'Release 打包临时资源已恢复。'
  }
}

function Assert-HapReleaseNotes {
  param([string]$HapPath, [string]$VersionName, [string]$ExpectedNotes)

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($HapPath)
  try {
    foreach ($name in @('version.json', 'releases.json')) {
      $entryPath = "resources/rawfile/update/$name"
      $entries = @($archive.Entries | Where-Object { $_.FullName -eq $entryPath })
      if ($entries.Count -ne 1) {
        throw "发行 HAP 缺少唯一的内置清单：$entryPath"
      }
      $reader = [IO.StreamReader]::new($entries[0].Open())
      try { $json = $reader.ReadToEnd() | ConvertFrom-Json -NoEnumerate } finally { $reader.Dispose() }
      if (($name -eq 'releases.json' -and $json -isnot [array]) -or
          ($name -eq 'version.json' -and $json -is [array])) {
        throw "发行 HAP 内置清单格式不正确：$entryPath"
      }
      $releases = @($json)
      $currentReleases = @($releases | Where-Object { $_.tag_name -eq "HMOSv$VersionName" })
      if ($releases.Count -eq 0 -or $releases[0].tag_name -ne "HMOSv$VersionName" -or $currentReleases.Count -ne 1) {
        throw "发行 HAP 内置清单缺少唯一的当前版本 HMOSv${VersionName}：$entryPath"
      }
      $body = ConvertTo-NormalizedReleaseNotes $currentReleases[0].body
      if ([string]::IsNullOrWhiteSpace($body) -or
          $body -cne (ConvertTo-NormalizedReleaseNotes $ExpectedNotes)) {
        throw "发行 HAP 的 HMOSv$VersionName 内置说明与发布文稿不一致：$entryPath"
      }
      if (@($currentReleases[0].assets).Count -ne 0 -or -not [string]::IsNullOrEmpty($currentReleases[0].published_at)) {
        throw "发行 HAP 当前版本内置了过期附件信息：$entryPath"
      }
    }
  } finally {
    $archive.Dispose()
  }
  Write-Host "发行 HAP 内置 HMOSv$VersionName 完整说明校验通过：$(Split-Path -Leaf $HapPath)"
}
