# Makes Windows open .mcgraph files with the MetalCreator.exe in this folder, for the current user (no administrator rights:
# it writes under HKEY_CURRENT_USER\Software\Classes). Run it from the extracted folder, and again after moving the folder.
# `register-mcgraph.ps1 -Remove` undoes it. Explorer passes the file as the first argument, which the app opens
# (cross-platform spec section 5, gap XP-G5; MetalUI docs/packaging.md, "Windows: a file association").
param([switch]$Remove)
$ErrorActionPreference = 'Stop'

$progId = 'MetalCreator.Graph'
$classes = 'HKCU:\Software\Classes'
$exe = Join-Path $PSScriptRoot 'MetalCreator.exe'

if ($Remove) {
    Remove-Item -Recurse -Force "$classes\.mcgraph", "$classes\$progId" -ErrorAction SilentlyContinue
    Write-Output 'Removed the .mcgraph association.'
    exit 0
}
if (-not (Test-Path $exe)) { throw "MetalCreator.exe isn't beside this script: $exe" }

New-Item -Force -Path "$classes\.mcgraph" -Value $progId | Out-Null
New-Item -Force -Path "$classes\$progId" -Value 'MetalCreator Graph' | Out-Null
New-Item -Force -Path "$classes\$progId\DefaultIcon" -Value "`"$exe`",0" | Out-Null
New-Item -Force -Path "$classes\$progId\shell\open\command" -Value "`"$exe`" `"%1`"" | Out-Null
Write-Output "Registered $exe for .mcgraph files."
