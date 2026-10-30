# Builds dist\MetalCreator-<version>-windows-x64.zip: a release build of MetalCreatorApp as MetalCreator.exe, every DLL it
# needs beside it (OpenCascade's, SDL3's, the Swift runtime's, the Visual C++ runtime's), MetalUI's compiled SDL shaders in
# MetalUISDLShaders, the 3D viewport's in MetalUIAppShaders, the implicit engine's shader compiler (SDL3_shadercross.dll, dxcompiler.dll, dxil.dll,
# spirv-cross-c-shared.dll; plan xp-c task 12, MetalUI docs/packaging.md 4b) beside the .exe, the .mcgraph file-type script and the licences. The zip is then unpacked into a scratch folder and
# `MetalCreator.exe --self-test` runs from there with a PATH that holds only Windows' own folders, so a DLL that is missing
# from the zip fails the build instead of the user's machine. A second arm unpacks it again without SDL3_shadercross.dll and requires
# `--self-test` to fail naming the missing compiler.
#
# usage (from the repository, in PowerShell on Windows; CI's Windows job runs it):
#   scripts\package-windows.ps1 [-NoBuild] -BuildFlags @(…) -SdlRoot <SDL3 VC package folder> -ShaderCrossRoot <SDL_shadercross prefix>
#   -BuildFlags  the extra swift build arguments the job already passes (SDL's and AccessKit's paths).
#   -SdlRoot     the SDL3-<version> folder of SDL's VC package (SDL3.dll in lib\x64, LICENSE.txt at the top).
#   -ShaderCrossRoot  scripts\install-shadercross.ps1's -Prefix: bin\ holds the four DLLs of the run-time shader compiler, share\licenses their texts.
#   -OutDir      where the zip is written (default: <repo>\dist).
#   -NoBuild     the release build was made by an earlier step (`swift build -c release --product MetalCreatorApp`, same flags):
#                only look its folder up. CI does this, so that a failed release build is its own red step.
# Environment: OCCT_PREFIX is OpenCascade's install root (bin\*.dll, share\opencascade\copyright); this script uses its release
# set (`bin`), never `debug\bin`.
# Needs MetalUI beside this repository (..\MetalUI) and the viewport's shaders, which the release build compiles through MetalUI's
# CompileShadersOnBuild plugin (METALUI_SHADERCROSS names shadercross; CI sets it for the job). Not run outside CI.
param(
    [string[]]$BuildFlags = @(),
    [Parameter(Mandatory)][string]$SdlRoot,
    [Parameter(Mandatory)][string]$ShaderCrossRoot,
    [string]$OutDir = (Join-Path $PSScriptRoot '..\dist'),
    [switch]$NoBuild
)
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$metalUI = (Resolve-Path (Join-Path $root '..\MetalUI')).Path
if (-not $env:OCCT_PREFIX) { throw 'OCCT_PREFIX must name the OpenCascade install root.' }
$work = Join-Path ([IO.Path]::GetTempPath()) "metalcreator-package-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $work | Out-Null

# The shader compiler's commit, for NOTICE.txt (the one pin: scripts\shadercross.env).
$pin = @{}
foreach ($line in Get-Content (Join-Path $PSScriptRoot 'shadercross.env')) {
    if ($line -match '^([A-Z_]+)=(.*)$') { $pin[$Matches[1]] = $Matches[2].Trim() }
}
if (-not $pin.SHADERCROSS_COMMIT) { throw 'scripts\shadercross.env names no SHADERCROSS_COMMIT' }

function Step($text) { Write-Output "==> $text" }

Step 'Building MetalCreatorApp (release)'
Push-Location $root
try {
    if (-not $NoBuild) {
        swift build -c release --product MetalCreatorApp @BuildFlags
        if ($LASTEXITCODE) { throw "swift build failed ($LASTEXITCODE)" }
    }
    $bin = (swift build -c release --product MetalCreatorApp @BuildFlags --show-bin-path).Trim()
} finally { Pop-Location }

$exe = Join-Path $bin 'MetalCreatorApp.exe'
if (-not (Test-Path $exe)) { throw "no release build at $exe (run swift build -c release --product MetalCreatorApp first)" }
# The folder is named after the version, which is read below from the assembled executable (not from the build tree, where the
# job's PATH holds vcpkg's debug\bin and the release exe could load debug OpenCascade DLLs); so it is staged under a plain name.
$folder = Join-Path $work 'stage'
New-Item -ItemType Directory -Path $folder | Out-Null

Step 'Assembling'
Copy-Item $exe (Join-Path $folder 'MetalCreator.exe')
Copy-Item (Join-Path $root 'packaging\windows\register-mcgraph.ps1') $folder
$shaders = Join-Path $metalUI 'Backends\SDL\Shaders\compiled'
if (-not (Test-Path (Join-Path $shaders 'SOURCE.sha256'))) { throw "MetalUI's compiled shaders are missing: $shaders" }
Copy-Item -Recurse $shaders (Join-Path $folder 'MetalUISDLShaders')
# The 3D viewport's own shaders (plan xp-3, user decision U7(a)): MetalUIAppShaders beside the executable, where the SDL renderer looks
# first. A build product, never in git: the release build's plugin made them in CreatorViewport's resource bundle beside the executable.
$appShaders = Join-Path $bin 'MetalCreator_CreatorViewport.bundle\MetalUIAppShaders'
if (-not (Test-Path (Join-Path $appShaders 'SOURCE.sha256'))) { throw "the viewport's compiled shaders are missing ($appShaders): the build needs SDL_shadercross (METALUI_SHADERCROSS)" }
Copy-Item -Recurse $appShaders (Join-Path $folder 'MetalUIAppShaders')

# The implicit engine's run-time shader compiler (plan xp-c task 12; MetalUI docs/packaging.md 4b): MetalUI finds SDL3_shadercross.dll beside the
# executable and preloads its dependents by full path. Each is enqueued below, so the dependents walk bundles what they need (the Visual C++
# runtime) and finds SDL3.dll already bundled: $ShaderCrossRoot\bin is not a search directory, so the prefix's own SDL3.dll is never copied.
$compilerDlls = 'SDL3_shadercross.dll', 'dxcompiler.dll', 'dxil.dll', 'spirv-cross-c-shared.dll'
foreach ($dll in $compilerDlls) {
    $from = Join-Path $ShaderCrossRoot "bin\$dll"
    if (-not (Test-Path $from)) { throw "the shader compiler's $dll is missing from $ShaderCrossRoot\bin (scripts\install-shadercross.ps1)" }
    Copy-Item $from (Join-Path $folder $dll)
}

Step 'Copying the DLLs it needs, transitively'

# The folders that hold the Swift runtime's DLLs, found by looking for swiftCore.dll, not by a path written down here: the
# toolchain installer, the setup-swift action and a side-by-side install all lay the runtime out differently, but under a
# folder named Swift that swift.exe's and SDKROOT's own folders sit below.
function Find-SwiftRuntimeDirs {
    $roots = [System.Collections.Generic.List[string]]::new()
    foreach ($start in @((Split-Path (Get-Command swift).Source), $env:SDKROOT)) {
        for ($dir = $start; $dir; $dir = [IO.Path]::GetDirectoryName($dir)) {
            if ([IO.Path]::GetFileName($dir) -eq 'Swift') { $roots.Add($dir); break }
        }
    }
    foreach ($known in @((Join-Path $env:ProgramFiles 'Swift'), (Join-Path $env:LOCALAPPDATA 'Programs\Swift'))) {
        if (Test-Path $known) { $roots.Add($known) }
    }
    $found = $roots | Select-Object -Unique | ForEach-Object {
        Get-ChildItem $_ -Recurse -Depth 6 -Filter swiftCore.dll -ErrorAction SilentlyContinue | ForEach-Object DirectoryName
    } | Select-Object -Unique
    if (-not $found) { throw "swiftCore.dll isn't under any of: $($roots -join ', ')" }
    $found
}

# What lists a binary's dependent DLLs: llvm-objdump (beside swift.exe, or on PATH), else dumpbin from Visual Studio.
function Find-DependentsTool {
    $beside = Join-Path (Split-Path (Get-Command swift).Source) 'llvm-objdump.exe'
    if (Test-Path $beside) { return @{ Kind = 'objdump'; Path = $beside } }
    $onPath = Get-Command llvm-objdump.exe -ErrorAction SilentlyContinue
    if ($onPath) { return @{ Kind = 'objdump'; Path = $onPath.Source } }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $dumpbin = & $vswhere -latest -products * -find 'VC\Tools\MSVC\**\bin\Hostx64\x64\dumpbin.exe' | Select-Object -First 1
        if ($dumpbin) { return @{ Kind = 'dumpbin'; Path = $dumpbin } }
    }
    throw 'neither llvm-objdump.exe (beside swift.exe or on PATH) nor Visual Studio''s dumpbin.exe was found'
}

$tool = Find-DependentsTool
# `-CaseSensitive`: llvm-objdump prints the executable's own export table as "DLL name: <exe>", which is not a dependency.
function Get-Dependents($file) {
    if ($tool.Kind -eq 'objdump') {
        & $tool.Path -p $file | Select-String -CaseSensitive 'DLL Name: (.+)$' | ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() }
    } else {
        & $tool.Path /nologo /dependents $file | ForEach-Object { if ($_ -match '^\s+(\S+\.dll)\s*$') { $Matches[1] } }
    }
}

# Where a dependency may come from: OpenCascade's release DLLs, SDL3, then the Swift toolchain's and runtime's folders.
$searchDirs = @(
    (Join-Path $env:OCCT_PREFIX 'bin'),
    (Join-Path $SdlRoot 'lib\x64'),
    (Split-Path (Get-Command swift).Source)
) + @(Find-SwiftRuntimeDirs)
Write-Output "    dependents from $($tool.Path); search path:"
$searchDirs | ForEach-Object { "      $_" }
$system = Join-Path $env:SystemRoot 'System32'
# The Visual C++ runtime is redistributable app-local; everything else in System32 is Windows' own.
$redistributable = '^(vcruntime140.*|msvcp140.*|concrt140|vcomp140)\.dll$'

$queue = [System.Collections.Generic.Queue[string]]::new()
$queue.Enqueue((Join-Path $folder 'MetalCreator.exe'))
$bundled = @{}
# Already beside the executable (copied above), so a DLL that imports one (SDL3_shadercross.dll imports spirv-cross-c-shared.dll) finds it bundled.
foreach ($dll in $compilerDlls) { $queue.Enqueue((Join-Path $folder $dll)); $bundled[$dll.ToLowerInvariant()] = $true }
while ($queue.Count) {
    $file = $queue.Dequeue()
    foreach ($dll in Get-Dependents $file) {
        if ($dll -notlike '*.dll') { continue }   # the executable's own export-table name, if the tool lists it
        $key = $dll.ToLowerInvariant()
        if ($bundled.ContainsKey($key) -or $key -like 'api-ms-win-*' -or $key -like 'ext-ms-*') { continue }
        $source = $searchDirs | ForEach-Object { Join-Path $_ $dll } | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $source -and $key -match $redistributable) { $source = Join-Path $system $dll }
        if (-not $source) {
            if (Test-Path (Join-Path $system $dll)) { continue }   # Windows' own
            throw "can't find $dll, needed by $file"
        }
        Copy-Item $source (Join-Path $folder $dll)
        $bundled[$key] = $true
        $queue.Enqueue((Join-Path $folder $dll))
    }
}
"    $($bundled.Count) DLLs"
if (-not $bundled.ContainsKey('tkernel.dll')) { throw "OpenCascade's TKernel.dll isn't among the DLLs the executable needs" }
if (-not $bundled.ContainsKey('sdl3.dll')) { throw "SDL3.dll isn't among the DLLs the executable needs" }
if (-not $bundled.ContainsKey('swiftcore.dll')) { throw "swiftCore.dll isn't among the DLLs the executable needs" }

Step 'Reading the version from the assembled executable, with only Windows on PATH'
$savedPath = $env:PATH
$env:PATH = "$system;$env:SystemRoot"
try {
    $versionLine = (& (Join-Path $folder 'MetalCreator.exe') --version)
    $versionCode = $LASTEXITCODE
} finally { $env:PATH = $savedPath }
if ($versionCode) { throw "--version failed from the assembled folder (exit $versionCode)" }
if ($versionLine -notmatch '^MetalCreator (\S+) ') { throw "can't read the version from: $versionLine" }
$version = $Matches[1]
$name = "MetalCreator-$version-windows-x64"
Rename-Item $folder $name
$folder = Join-Path $work $name

Step 'Copying the licences'
$doc = Join-Path $folder 'licenses'
New-Item -ItemType Directory -Path $doc | Out-Null
# vcpkg's opencascade port installs LICENSE_LGPL_21.txt and OCCT_LGPL_EXCEPTION.txt as share\opencascade\copyright
# (vcpkg_install_copyright). Say so only if it is so: the file must exist and hold both the LGPL and the exception.
$occtCopyright = Join-Path $env:OCCT_PREFIX 'share\opencascade\copyright'
if (-not (Test-Path $occtCopyright)) { throw "OpenCascade's licence is missing: $occtCopyright" }
$occtText = Get-Content $occtCopyright -Raw
if ($occtText -notmatch 'GNU LESSER GENERAL PUBLIC LICENSE' -or $occtText -notmatch 'exception') {
    throw "$occtCopyright doesn't hold the LGPL text and the OCCT exception"
}
Copy-Item $occtCopyright (Join-Path $doc 'OpenCascade-LGPL-2.1-with-OCCT-exception.txt')
$swiftLicense = Join-Path $root 'packaging\licenses\Swift-LICENSE.txt'
if (-not (Test-Path $swiftLicense)) { throw "the Swift licence is missing: $swiftLicense" }
Copy-Item $swiftLicense (Join-Path $doc 'Swift-LICENSE.txt')
if (-not (Test-Path (Join-Path $SdlRoot 'LICENSE.txt'))) { throw "SDL3's licence is missing: $SdlRoot\LICENSE.txt" }
Copy-Item (Join-Path $SdlRoot 'LICENSE.txt') (Join-Path $doc 'SDL3-LICENSE.txt')
# The shader compiler's licence texts (scripts\install-shadercross.ps1 leaves them in the prefix), in licenses\shader-compiler.
$compilerLicenses = Join-Path $ShaderCrossRoot 'share\licenses'
if (-not (Test-Path (Join-Path $compilerLicenses 'DirectXShaderCompiler'))) { throw "the shader compiler's licences are missing: $compilerLicenses" }
Copy-Item -Recurse $compilerLicenses (Join-Path $doc 'shader-compiler')
# NOTICE.txt: where OpenCascade's source is and that its DLLs may be replaced (LGPL-2.1 section 6). The vcpkg commit is the
# manifest's builtin-baseline, so the notice names the one the DLLs were built from.
$baseline = (Get-Content (Join-Path $root 'packaging\windows\vcpkg.json') -Raw | ConvertFrom-Json).'builtin-baseline'
if ($baseline -notmatch '^[0-9a-f]{40}$') { throw "packaging\windows\vcpkg.json has no builtin-baseline commit" }
$occtDlls = (Get-ChildItem $folder -Filter 'TK*.dll' | Sort-Object Name | ForEach-Object { "                $($_.Name)" }) -join "`n"
if (-not $occtDlls) { throw 'no TK*.dll in the package folder' }
@"
MetalCreator ${version}: third-party software shipped in this package

OpenCascade Technology (OCCT) 7.9
  Licence:   GNU LGPL version 2.1 with the OCCT exception (OpenCascade-LGPL-2.1-with-OCCT-exception.txt, in this folder).
  Source:    https://github.com/Open-Cascade-SAS/OCCT, tag V7_9_3, as built by vcpkg's "opencascade" port, version 7.9.3,
             port-version 1, at https://github.com/microsoft/vcpkg commit $baseline (ports/opencascade; the port's patches are there).
  Libraries: the DLLs
$occtDlls
             beside MetalCreator.exe.
  Relinking: OCCT is linked dynamically. You may replace those DLLs with your own build of OCCT 7.9, modified or not, and
             MetalCreator will use them (same names, x64, release, built with the same Visual C++ runtime).

SDL3 (SDL3.dll): zlib licence, SDL3-LICENSE.txt. Source: https://github.com/libsdl-org/SDL, tag release-$env:SDL_VERSION.

Swift runtime (swiftCore.dll, swift*.dll, Foundation*.dll and the DLLs they need): Apache License 2.0 with the Runtime Library
Exception, Swift-LICENSE.txt. Source: https://github.com/swiftlang/swift, release 6.4.

The implicit engine's shader compiler (SDL3_shadercross.dll, dxcompiler.dll, dxil.dll, spirv-cross-c-shared.dll), loaded while the app runs to
compile its generated HLSL (MetalUI's SDLGPUShaderCompiler); built from https://github.com/libsdl-org/SDL_shadercross, commit $($pin.SHADERCROSS_COMMIT),
with the submodules that commit fixes. The licence texts are in shader-compiler\ in this folder:
  SDL_shadercross                       zlib licence, shader-compiler\SDL3_shadercross
  DirectXShaderCompiler and dxil.dll    Microsoft's prebuilt DXC v1.9.2602, downloaded by SDL_shadercross's own build script at that commit;
                                        their licence files are in shader-compiler\DirectXShaderCompiler
  SPIRV-Cross                           Apache License 2.0, shader-compiler\SPIRV-Cross
  SPIRV-Tools (linked into the above)   Apache License 2.0, shader-compiler\SPIRV-Tools
  SPIRV-Headers (compiled in)           Khronos MIT-style licence, shader-compiler\SPIRV-Headers

Visual C++ runtime (vcruntime140*.dll, msvcp140*.dll): Microsoft's redistributable, shipped app-local under Microsoft's
Visual Studio redistribution terms.

MetalUI and the libraries it vendors (stb_image, FreeType, HarfBuzz, libunibreak, SheenBidi): MetalUI-THIRD-PARTY-NOTICES.md and the
licence files named after each library, in this folder. AccessKit is linked statically into the executable (MIT or Apache-2.0; its
licence text is not shipped yet: see MetalUI-THIRD-PARTY-NOTICES.md).
"@ | Set-Content -Path (Join-Path $doc 'NOTICE.txt') -Encoding utf8
Copy-Item (Join-Path $metalUI 'THIRD-PARTY-NOTICES.md') (Join-Path $doc 'MetalUI-THIRD-PARTY-NOTICES.md')
foreach ($f in 'CStbImage/LICENSE', 'CFreeType/FTL.TXT', 'CFreeType/LICENSE.TXT', 'CHarfBuzz/COPYING', 'CUnibreak/LICENCE', 'CSheenBidi/LICENSE') {
    Copy-Item (Join-Path $metalUI "Sources\$f") (Join-Path $doc ((Split-Path $f) + '-' + (Split-Path $f -Leaf)))
}

Step 'Writing the zip'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$zip = Join-Path (Resolve-Path $OutDir).Path "$name.zip"
Remove-Item -Force $zip -ErrorAction SilentlyContinue
Compress-Archive -Path $folder -DestinationPath $zip

Step 'Checking the zip on its own: --self-test with only Windows on PATH'
$check = Join-Path $work 'check'
Expand-Archive $zip -DestinationPath $check
$savedPath = $env:PATH
$savedLib = $env:METALUI_SHADERCROSS_LIB
$env:PATH = "$system;$env:SystemRoot"
# CI sets METALUI_SHADERCROSS_LIB for the tests; the zip must find its compiler beside the executable on its own.
Remove-Item Env:METALUI_SHADERCROSS_LIB -ErrorAction SilentlyContinue
# MetalUI's SDL backend falls back to the shaders in the source tree it was built from, which would hide a zip without
# MetalUISDLShaders, and the viewport falls back to the build's resource bundle (SwiftPM's accessor remembers its path), which would hide a zip without
# MetalUIAppShaders; so both are moved aside for the check.
$aside = "$metalUI.aside"
$appShadersAside = "$appShaders.aside"
Rename-Item $metalUI $aside
Rename-Item $appShaders $appShadersAside
try {
    & (Join-Path $check "$name\MetalCreator.exe") --self-test
    $code = $LASTEXITCODE
    # Without the compiler's library --self-test must fail at "implicit compiler" and name what is missing (MetalUI RC3, on our package).
    $without = Join-Path $work 'without'
    Copy-Item -Recurse (Join-Path $check $name) $without
    Remove-Item (Join-Path $without 'SDL3_shadercross.dll')
    # A native command's stderr becomes an error record under 'Stop' (Windows PowerShell 5.1), which would end the script before the checks below.
    $ErrorActionPreference = 'Continue'
    $withoutText = (& (Join-Path $without 'MetalCreator.exe') --self-test 2>&1 | Out-String)
    $withoutCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
} finally {
    Rename-Item $appShadersAside $appShaders
    Rename-Item $aside $metalUI
    $env:PATH = $savedPath
    if ($null -ne $savedLib) { $env:METALUI_SHADERCROSS_LIB = $savedLib }
}
if ($code) { throw "--self-test failed from the unpacked zip (exit $code)" }
if (-not $withoutCode) { throw "--self-test passed without SDL3_shadercross.dll: $withoutText" }
if ($withoutText -notmatch 'FAIL implicit compiler' -or $withoutText -notmatch 'shader compiler library not found') {
    throw "--self-test without SDL3_shadercross.dll did not fail at 'implicit compiler' naming the missing library: $withoutText"
}
Remove-Item -Recurse -Force $work
# The "without the library" run above exits 1 on purpose; a caller that ends with `exit $LASTEXITCODE` (CI does) must not see it.
$global:LASTEXITCODE = 0
Write-Output $zip
