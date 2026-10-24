function Assert-HapNoSourceMap {
  param([string]$HapPath)

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($HapPath)
  try {
    $maps = @($archive.Entries | Where-Object { $_.FullName -like 'ets/*.map' })
    if ($maps.Count -gt 0) {
      throw "发行 HAP 不应包含映射文件：$($maps.FullName -join '、')；$HapPath"
    }
  } finally {
    $archive.Dispose()
  }
  Write-Host "发行 HAP 不含源码或符号映射：$(Split-Path -Leaf $HapPath)"
}
