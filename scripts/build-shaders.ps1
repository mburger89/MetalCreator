<#
.SYNOPSIS
Compiles the viewport's SDL_GPU shaders on Windows (plan xp-3, user decision U1(b)): the HLSL in Shaders\viewport becomes SPIR-V,
DXIL and MSL, a reflection JSON each and SOURCE.sha256, in Shaders\viewport\compiled, through MetalUI's MetalUICompileShaders
(MetalUI S12, docs/packaging.md section 4a), built from ..\MetalUI with a scratch path of ours; this script adds INCLUDES.sha256 for the
shared header. Nothing compiled is checked in; CI runs this before `swift build`, and so does a developer, once and after editing an
.hlsl file.

.DESCRIPTION
SDL_shadercross is pinned in scripts\shadercross.env (scripts\install-shadercross.ps1 builds that commit; CI caches the result). Swift
and MetalUI beside this repository (..\MetalUI) are needed. Exit 69 when shadercross is missing or is not the pinned commit, 1 when a
shader fails to compile (the compiled directory is removed so the tests and --self-test fail loudly), 2 when MetalUI is missing.

    scripts\build-shaders.ps1 -ShaderCross C:\tools\shadercross\bin\shadercross.exe     (or set $env:SHADERCROSS, or put it on PATH)
#>
param([string]$ShaderCross = $env:SHADERCROSS)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pin = @{}
foreach ($line in Get-Content (Join-Path $PSScriptRoot 'shadercross.env')) {
    if ($line -match '^([A-Z_]+)=(.*)$') { $pin[$Matches[1]] = $Matches[2].Trim() }
}
$tool = "SDL_shadercross ($($pin.SHADERCROSS_REPOSITORY), commit $($pin.SHADERCROSS_COMMIT), pinned in scripts/shadercross.env)"
function Stop-Build([int]$code, [string]$message) {
    [Console]::Error.WriteLine("scripts/build-shaders.ps1: $message")
    exit $code
}

if (-not $ShaderCross) {
    $found = Get-Command shadercross.exe -ErrorAction SilentlyContinue
    if ($found) { $ShaderCross = $found.Source }
}
if (-not $ShaderCross -or -not (Test-Path $ShaderCross)) {
    Stop-Build 69 "$tool was not found. Pass -ShaderCross C:\path\shadercross.exe or set SHADERCROSS; scripts\install-shadercross.ps1 builds the pinned one. The viewport's shaders are compiled at build time and cannot be built without it."
}
# install-shadercross.ps1 records the commit it built beside bin\; any other build is refused.
$recorded = Join-Path (Split-Path -Parent (Split-Path -Parent $ShaderCross)) 'COMMIT'
if ((Test-Path $recorded) -and ((Get-Content $recorded -Raw).Trim() -ne $pin.SHADERCROSS_COMMIT)) {
    Stop-Build 69 "$ShaderCross was built from another commit than the one required: $tool. Rebuild it with scripts\install-shadercross.ps1."
}
$metalUI = Join-Path $root '..\MetalUI'
if (-not (Test-Path (Join-Path $metalUI 'Package.swift'))) { Stop-Build 2 'MetalUI must be checked out beside this repository (..\MetalUI), as Package.swift expects.' }
$metalUI = (Resolve-Path $metalUI).Path
$scratch = if ($env:METALUI_TOOLS_SCRATCH) { $env:METALUI_TOOLS_SCRATCH } else { Join-Path $root '.build\metalui-tools' }
$source = Join-Path $root 'Shaders\viewport'
$out = Join-Path $source 'compiled'

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
Write-Output "Compiling Shaders\viewport with MetalUI's MetalUICompileShaders and $tool..."
# Run from the shader directory, as build-shaders.sh does: shadercross hands DXC the source as "hlsl.hlsl" with no include path, so
# `#include "common.hlsli"` resolves against the working directory.
Push-Location $source
try {
    swift run --package-path $metalUI --scratch-path $scratch MetalUICompileShaders --shadercross $ShaderCross --source $source --out $out
} finally {
    Pop-Location
}
if ($LASTEXITCODE) {
    if (Test-Path $out) { Remove-Item $out -Recurse -Force }
    Stop-Build 1 "$tool failed to compile a shader of Shaders\viewport, or MetalUICompileShaders did not build (the lines above name the file). Shaders\viewport\compiled was removed."
}
# INCLUDES.sha256 in MetalUI's marker format: "<sha256>  <name>" per header, sorted by name, LF (ShaderSourceTests reads it as a table).
$lines = Get-ChildItem (Join-Path $source '*.hlsli') | Sort-Object Name | ForEach-Object {
    "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $($_.Name)"
}
[IO.File]::WriteAllText((Join-Path $out 'INCLUDES.sha256'), (($lines -join "`n") + "`n"))
Write-Output "Built Shaders\viewport\compiled ($((Get-ChildItem $out -File).Count) files)."
