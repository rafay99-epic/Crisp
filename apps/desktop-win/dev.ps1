<#
  Builds the CURRENT branch as the Dev channel and installs it next to Stable —
  the Windows counterpart of dev.sh. "Crisp Dev" gets its own name, data home
  (~/.crisp-dev), and Start-menu entry, so break it all you like without touching a
  Stable install. Extra args pass through to build.ps1 (e.g. -Vendor for the engine).
  Usage: .\dev.ps1  [-Vendor]
#>
& (Join-Path $PSScriptRoot 'build.ps1') -Channel dev -Install -Run @args
