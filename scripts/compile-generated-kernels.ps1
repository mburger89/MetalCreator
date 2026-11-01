<#
.SYNOPSIS
Compiles the implicit engine's generated HLSL kernels offline on Windows (plan xp-c, task 10b), the counterpart of scripts/compile-generated-kernels.sh:
the sources GeneratedKernelExport wrote to .build\generated-kernels\source become SPIR-V, DXIL, MSL and reflection JSON in
.build\generated-kernels\compiled, through MetalUI's MetalUICompileShaders and the pinned SDL_shadercross (scripts\shadercross.env). Only the
sources not compiled yet are compiled (a name is its text's digest). CI runs it before `swift test`, which also validates every kernel through DXC
and DXIL. A source DXC refuses stops the script (exit 1): that is a generator bug, never a test to skip.

.DESCRIPTION
Run `$env:XP_EXPORT_KERNELS = '1'; swift test --filter GeneratedKernelExport` first (CI does) to write the sources. Exit 69 when shadercross is
missing or is not the pinned commit, 2 when MetalUI is missing, 1 when a kernel fails to compile.

    scripts\compile-generated-kernels.ps1 -ShaderCross C:\tools\shadercross\bin\shadercross.exe     (or set $env:SHADERCROSS, or put it on PATH)
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
    [Console]::Error.WriteLine("scripts/compile-generated-kernels.ps1: $message")
    exit $code
}

if (-not $ShaderCross) {
    $found = Get-Command shadercross.exe -ErrorAction SilentlyContinue
    if ($found) { $ShaderCross = $found.Source }
}
if (-not $ShaderCross -or -not (Test-Path $ShaderCross)) {
    Stop-Build 69 "$tool was not found. Pass -ShaderCross C:\path\shadercross.exe or set SHADERCROSS; scripts\install-shadercross.ps1 builds the pinned one."
}
$recorded = Join-Path (Split-Path -Parent (Split-Path -Parent $ShaderCross)) 'COMMIT'
if ((Test-Path $recorded) -and ((Get-Content $recorded -Raw).Trim() -ne $pin.SHADERCROSS_COMMIT)) {
    Stop-Build 69 "$ShaderCross was built from another commit than the one required: $tool. Rebuild it with scripts\install-shadercross.ps1."
}
$metalUI = Join-Path $root '..\MetalUI'
if (-not (Test-Path (Join-Path $metalUI 'Package.swift'))) { Stop-Build 2 'MetalUI must be checked out beside this repository (..\MetalUI), as Package.swift expects.' }
$metalUI = (Resolve-Path $metalUI).Path
$scratch = if ($env:METALUI_TOOLS_SCRATCH) { $env:METALUI_TOOLS_SCRATCH } else { Join-Path $root '.build\metalui-tools' }
$kernels = Join-Path $root '.build\generated-kernels'
$compiled = Join-Path $kernels 'compiled'
$stage = Join-Path $kernels 'stage'
New-Item -ItemType Directory -Force $compiled | Out-Null
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force $stage | Out-Null

# The sources whose reflection JSON is not there yet (a name is the digest of its text).
$sourceDir = Join-Path $kernels 'source'
$pending = @()
if (Test-Path $sourceDir) {
    $pending = @(Get-ChildItem $sourceDir -Filter '*.comp.hlsl' -File | Where-Object {
        $stem = $_.Name.Substring(0, $_.Name.Length - '.hlsl'.Length)
        -not (Test-Path (Join-Path $compiled "$stem.json")) -or (Get-Item (Join-Path $compiled "$stem.json")).Length -eq 0
    })
}
if ($pending.Count -eq 0) { Write-Output 'The generated kernels are compiled.'; exit 0 }
$pending | Copy-Item -Destination $stage
Write-Output "Compiling $($pending.Count) generated kernels..."

# Run from the staging directory, as MetalUI's tool does from a source's directory: shadercross hands DXC the source with no include path.
$out = Join-Path $stage 'out'
$watch = [Diagnostics.Stopwatch]::StartNew()
Push-Location $stage
try {
    swift run --package-path $metalUI --scratch-path $scratch MetalUICompileShaders --no-marker --shadercross $ShaderCross --source $stage --out $out
    $code = $LASTEXITCODE
} finally {
    Pop-Location
}
if ($code) {
    Stop-Build 1 "$tool failed to compile a generated kernel, or MetalUICompileShaders did not build (the lines above name the file). A kernel DXC refuses is a generator bug."
}
Copy-Item (Join-Path $out '*') -Destination $compiled -Force
Write-Output "COMPILE-TIME $($pending.Count) kernels in $([math]::Round($watch.Elapsed.TotalSeconds, 1)) s"
