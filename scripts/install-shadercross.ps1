<#
.SYNOPSIS
Builds the pinned SDL_shadercross for Windows x64 (plan xp-3, user decision U1(b)) into -Prefix, so scripts\build-shaders.ps1 can
compile the viewport's shaders. CI runs it once per pin and caches the prefix with actions/cache; a developer runs it once.

.DESCRIPTION
The repository has no release or tag, so the pin is the commit in scripts\shadercross.env; the commit fixes the SPIRV-Cross,
SPIRV-Headers and SPIRV-Tools submodules and Microsoft's prebuilt DirectXShaderCompiler (downloaded by the commit's own cmake script,
by URL and SHA-256). It needs cmake, ninja and git on PATH (the windows-latest runner has them) and Visual Studio's C++ tools (entered below when cl is not
on PATH). SDL3's development package (its cmake files) is -Sdl3Root.

    scripts\install-shadercross.ps1 -Prefix C:\tools\shadercross -Sdl3Root C:\SDL3-3.4.16

It leaves <Prefix>\bin\shadercross.exe with its DLLs and <Prefix>\COMMIT, which build-shaders.ps1 compares with the pin. It also leaves the
implicit engine's run-time compiler (plan xp-c task 12, MetalUI docs/packaging.md 4b): SDL3_shadercross.dll, dxcompiler.dll, dxil.dll and
spirv-cross-c-shared.dll, all in <Prefix>\bin, and their licences in <Prefix>\share\licenses. Outside a developer
shell it enters one itself (Visual Studio's DevShell module, found with vswhere), for this script's process only, so CI needs no action
for it and the later swift steps see the environment they always saw.
#>
param(
    [Parameter(Mandatory)][string]$Prefix,
    [Parameter(Mandatory)][string]$Sdl3Root,
    [string]$Work = (Join-Path $env:TEMP 'shadercross-src')
)
$ErrorActionPreference = 'Stop'
$pin = @{}
foreach ($line in Get-Content (Join-Path $PSScriptRoot 'shadercross.env')) {
    if ($line -match '^([A-Z_]+)=(.*)$') { $pin[$Matches[1]] = $Matches[2].Trim() }
}
if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    $vs = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -property installationPath
    if (-not $vs) { throw 'Visual Studio was not found (vswhere): SDL_shadercross needs its C++ compiler.' }
    Import-Module (Join-Path $vs 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
    Enter-VsDevShell -VsInstallPath $vs -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64' | Out-Null
}
function Invoke-Step([string]$what, [scriptblock]$command) {
    & $command
    if ($LASTEXITCODE) {
        [Console]::Error.WriteLine("scripts/install-shadercross.ps1: $what failed (exit $LASTEXITCODE) while building SDL_shadercross $($pin.SHADERCROSS_COMMIT) ($($pin.SHADERCROSS_REPOSITORY), pinned in scripts/shadercross.env).")
        exit 1
    }
}

if (Test-Path $Work) { Remove-Item $Work -Recurse -Force }
New-Item -ItemType Directory $Work | Out-Null
Invoke-Step 'git init' { git init $Work }
Invoke-Step 'git remote' { git -C $Work remote add origin $pin.SHADERCROSS_REPOSITORY }
Invoke-Step 'git fetch of the pinned commit' { git -C $Work fetch --depth 1 origin $pin.SHADERCROSS_COMMIT }
Invoke-Step 'git checkout' { git -C $Work checkout FETCH_HEAD }
Invoke-Step 'git submodules' { git -C $Work submodule update --init --depth 1 external/SPIRV-Cross external/SPIRV-Headers external/SPIRV-Tools }
$spirvPrefix = Join-Path $Work 'spirv_cross_prefix'
$dxc = Join-Path $Work 'external/DirectXShaderCompiler-binaries'
Push-Location $Work
try {
    Invoke-Step 'the DirectXShaderCompiler download' { cmake -P build-scripts/download-prebuilt-DirectXShaderCompiler.cmake }
    Invoke-Step 'SPIRV-Cross (configure)' { cmake -S external/SPIRV-Cross -B spirv_cross_build -G Ninja -DCMAKE_BUILD_TYPE=Release -DSPIRV_CROSS_SHARED=ON -DSPIRV_CROSS_STATIC=ON -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_TESTS=OFF "-DCMAKE_INSTALL_PREFIX=$spirvPrefix" }
    Invoke-Step 'SPIRV-Cross (build)' { cmake --build spirv_cross_build }
    Invoke-Step 'SPIRV-Cross (install)' { cmake --install spirv_cross_build }
    Invoke-Step 'SDL_shadercross (configure)' {
        cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DSDLSHADERCROSS_VENDORED=OFF -DSDLSHADERCROSS_CLI=ON `
            -DSDLSHADERCROSS_SHARED=ON -DSDLSHADERCROSS_STATIC=OFF -DSDLSHADERCROSS_INSTALL=ON -DSDLSHADERCROSS_INSTALL_RUNTIME=ON `
            "-DCMAKE_PREFIX_PATH=$Sdl3Root" "-DDirectXShaderCompiler_ROOT=$dxc" `
            "-Dspirv_cross_c_shared_ROOT=$spirvPrefix;$spirvPrefix/share/spirv_cross_c_shared" "-DCMAKE_INSTALL_PREFIX=$Prefix"
    }
    Invoke-Step 'SDL_shadercross (build)' { cmake --build build }
    Invoke-Step 'SDL_shadercross (install)' { cmake --install build }
} finally {
    Pop-Location
}
# The implicit engine's run-time compiler (plan xp-c task 12, MetalUI docs/packaging.md 4b) is these four DLLs, all in bin, with their licences.
$bin = Join-Path $Prefix 'bin'
$spirvDll = Join-Path $spirvPrefix 'bin\spirv-cross-c-shared.dll'
if (-not (Test-Path (Join-Path $bin 'spirv-cross-c-shared.dll')) -and (Test-Path $spirvDll)) { Copy-Item $spirvDll $bin }
foreach ($dll in 'SDL3_shadercross.dll', 'dxcompiler.dll', 'dxil.dll', 'spirv-cross-c-shared.dll') {
    if (-not (Test-Path (Join-Path $bin $dll))) { throw "the SDL_shadercross install left no $dll in $bin" }
}
$licenses = Join-Path $Prefix 'share\licenses'
New-Item -ItemType Directory -Force (Join-Path $licenses 'DirectXShaderCompiler'), (Join-Path $licenses 'SPIRV-Cross'),
    (Join-Path $licenses 'SPIRV-Tools'), (Join-Path $licenses 'SPIRV-Headers'), (Join-Path $licenses 'SDL3_shadercross') | Out-Null
$dxcLicences = Get-ChildItem $dxc -Recurse -File | Where-Object { $_.Name -match '^(LICENSE|ThirdPartyNotices)' }
if (-not $dxcLicences) { throw "no licence file in the DirectXShaderCompiler download ($dxc)" }
$dxcLicences | ForEach-Object { Copy-Item $_.FullName (Join-Path $licenses 'DirectXShaderCompiler') }
Copy-Item (Join-Path $Work 'external\SPIRV-Cross\LICENSE') (Join-Path $licenses 'SPIRV-Cross')
Copy-Item (Join-Path $Work 'external\SPIRV-Tools\LICENSE') (Join-Path $licenses 'SPIRV-Tools')
Copy-Item (Join-Path $Work 'external\SPIRV-Headers\LICENSE') (Join-Path $licenses 'SPIRV-Headers')
Copy-Item (Join-Path $Work 'LICENSE.txt') (Join-Path $licenses 'SDL3_shadercross')
Set-Content -Path (Join-Path $Prefix 'COMMIT') -Value $pin.SHADERCROSS_COMMIT
Write-Output "SDL_shadercross $($pin.SHADERCROSS_COMMIT) is in $Prefix."
