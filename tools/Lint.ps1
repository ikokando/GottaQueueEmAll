# Checks the addon's Lua with luacheck (settings: ..\.luacheckrc).
# luacheck.exe: https://github.com/lunarmodules/luacheck/releases (v1.2.0),
# by default in %LOCALAPPDATA%\wowdev. Exit code 0 = no warnings.
param([string]$Luacheck = "$env:LOCALAPPDATA\wowdev\luacheck.exe")

if (-not (Test-Path $Luacheck)) { Write-Error "luacheck not found: $Luacheck"; exit 2 }
Push-Location (Split-Path $PSScriptRoot)
try {
    & $Luacheck . --codes
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
