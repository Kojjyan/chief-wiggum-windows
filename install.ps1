# Install Chief Wiggum on Windows
# Run from PowerShell: .\install.ps1

$ErrorActionPreference = "Stop"

$WIGGUM_HOME = "$env:USERPROFILE\.claude\chief-wiggum"
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Installing Chief Wiggum to $WIGGUM_HOME" -ForegroundColor Green
Write-Host ""

# Check prerequisites
function Test-Prerequisites {
    $required = @{
        "git" = "Git for Windows (https://git-scm.com/download/win)"
        "bash" = "Git Bash (comes with Git for Windows)"
        "jq" = "choco install jq OR winget install jqlang.jq"
        "gh" = "choco install gh OR winget install GitHub.cli"
        "curl" = "Should be included with Git for Windows"
    }

    $missing = @()

    foreach ($cmd in $required.Keys) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            $missing += "$cmd - $($required[$cmd])"
        }
    }

    # Check for Claude CLI
    if (-not (Get-Command "claude" -ErrorAction SilentlyContinue)) {
        $missing += "claude - https://docs.anthropic.com/en/docs/claude-code"
    }

    if ($missing.Count -gt 0) {
        Write-Host "Missing prerequisites:" -ForegroundColor Red
        foreach ($m in $missing) {
            Write-Host "  - $m" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "Please install the missing tools and run this script again." -ForegroundColor Red
        exit 1
    }

    Write-Host "All prerequisites found" -ForegroundColor Green
}

# Check Windows-specific tools
function Test-WindowsTools {
    $tools = @("tasklist", "powershell", "wmic", "taskkill")
    $missing = @()

    foreach ($tool in $tools) {
        $cmd = "$tool.exe"
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            $missing += $cmd
        }
    }

    if ($missing.Count -gt 0) {
        Write-Host "Warning: Some Windows tools are missing (these should be in System32):" -ForegroundColor Yellow
        foreach ($m in $missing) {
            Write-Host "  - $m" -ForegroundColor Yellow
        }
    }
}

# Install uv if not present
function Install-Uv {
    if (Get-Command "uv" -ErrorAction SilentlyContinue) {
        Write-Host "uv is already installed" -ForegroundColor Green
        return
    }

    Write-Host "Installing uv (Python package manager)..." -ForegroundColor Cyan
    try {
        Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression

        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "User") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "Machine")

        if (-not (Get-Command "uv" -ErrorAction SilentlyContinue)) {
            Write-Host "Warning: uv installed but not in PATH. You may need to restart your terminal." -ForegroundColor Yellow
        } else {
            Write-Host "uv installed successfully" -ForegroundColor Green
        }
    } catch {
        Write-Host "Warning: Failed to install uv. TUI features will not work." -ForegroundColor Yellow
        Write-Host "Install manually: https://docs.astral.sh/uv/getting-started/installation/" -ForegroundColor Yellow
    }
}

# Copy files
function Copy-Files {
    Write-Host "Copying files..." -ForegroundColor Cyan

    # Create target directory
    New-Item -ItemType Directory -Force -Path $WIGGUM_HOME | Out-Null

    # Copy directories
    $dirs = @("bin", "lib", "hooks", "skills", "config", "tui")
    foreach ($dir in $dirs) {
        $src = Join-Path $SCRIPT_DIR $dir
        $dst = Join-Path $WIGGUM_HOME $dir
        if (Test-Path $src) {
            Copy-Item -Path $src -Destination $WIGGUM_HOME -Recurse -Force
            Write-Host "  Copied $dir" -ForegroundColor Gray
        }
    }
}

# Setup TUI Python environment
function Setup-Tui {
    $tuiDir = Join-Path $WIGGUM_HOME "tui"
    $pyproject = Join-Path $tuiDir "pyproject.toml"

    if ((Test-Path $tuiDir) -and (Test-Path $pyproject)) {
        if (Get-Command "uv" -ErrorAction SilentlyContinue) {
            Write-Host "Setting up TUI Python environment..." -ForegroundColor Cyan
            Push-Location $tuiDir
            try {
                uv sync
                Write-Host "TUI environment ready" -ForegroundColor Green
            } catch {
                Write-Host "Warning: Failed to setup TUI environment" -ForegroundColor Yellow
            }
            Pop-Location
        }
    }
}

# Add to PATH
function Add-ToPath {
    $binPath = Join-Path $WIGGUM_HOME "bin"
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")

    if ($currentPath -notlike "*$binPath*") {
        Write-Host "Adding $binPath to user PATH..." -ForegroundColor Cyan
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$binPath", "User")
        $env:Path = "$env:Path;$binPath"
        Write-Host "Added to PATH" -ForegroundColor Green
    } else {
        Write-Host "$binPath already in PATH" -ForegroundColor Green
    }
}

# Main installation
Write-Host "=== Checking Prerequisites ===" -ForegroundColor Blue
Test-Prerequisites
Test-WindowsTools

Write-Host ""
Write-Host "=== Installing uv ===" -ForegroundColor Blue
Install-Uv

Write-Host ""
Write-Host "=== Copying Files ===" -ForegroundColor Blue
Copy-Files

Write-Host ""
Write-Host "=== Setting up TUI ===" -ForegroundColor Blue
Setup-Tui

Write-Host ""
Write-Host "=== Updating PATH ===" -ForegroundColor Blue
Add-ToPath

Write-Host ""
Write-Host "=== Installation Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Installed to: $WIGGUM_HOME" -ForegroundColor Cyan
Write-Host ""
Write-Host "IMPORTANT: Chief Wiggum requires Git Bash to run." -ForegroundColor Yellow
Write-Host "Open Git Bash and run:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  cd /path/to/your/project" -ForegroundColor White
Write-Host "  wiggum init" -ForegroundColor White
Write-Host "  wiggum run" -ForegroundColor White
Write-Host ""
Write-Host "To verify installation, open a new Git Bash window and run:" -ForegroundColor Cyan
Write-Host "  wiggum --version" -ForegroundColor White
Write-Host ""
