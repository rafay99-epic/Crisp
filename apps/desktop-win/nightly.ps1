<#
  Builds the CURRENT branch as the Nightly channel and installs it next to Stable
  (and Dev) — the Windows counterpart of nightly.sh. Use it to smoke-test a Nightly
  build locally before pushing to the `nightly` branch. A local build has build
  number 0, so it'll offer to pull the published Nightly. Extra args pass through to
  build.ps1 (e.g. -Vendor for the engine).
  Usage: .\nightly.ps1  [-Vendor]
#>
& (Join-Path $PSScriptRoot 'build.ps1') -Channel nightly -Install -Run @args
