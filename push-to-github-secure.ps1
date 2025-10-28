param(
    [string]$RepoOwner = "palakprakashh13",
    [string]$RepoName = "mgnrega-dashboard",
    [string]$RemoteUrl = "",
    [string]$CommitMessage = "Initial commit: MGNREGA Dashboard",
    [string]$Branch = "main",
    [switch]$ForceRemote
)

function Write-ErrorAndExit {
    param([string]$Msg)
    Write-Host "ERROR: $Msg" -ForegroundColor Red
    exit 1
}

Write-Host "push-to-github-secure.ps1 — securely push local project to GitHub (uses a temporary askpass helper)" -ForegroundColor Cyan

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-ErrorAndExit "Git is not installed or not in PATH. Install Git and re-run this script."
}

# Determine remote url
if ([string]::IsNullOrWhiteSpace($RemoteUrl)) {
    $RemoteUrl = "https://github.com/$RepoOwner/$RepoName.git"
}

# Initialize git repo if needed
if (-not (Test-Path .git)) {
    Write-Host "Initializing git repository..."
    git init || Write-ErrorAndExit "Failed to initialize git repository."
} else {
    Write-Host ".git already exists — using existing repository."
}

# Create a basic .gitignore if none exists
if (-not (Test-Path .gitignore)) {
    Write-Host "Creating a recommended .gitignore..."
    @"
# Node
node_modules/
.env
npm-debug.log
package-lock.json

# Python
__pycache__/
*.pyc

# Logs
logs/
*.log

# VSCode
.vscode/

# Mac
.DS_Store

# Windows
Thumbs.db

# Build
dist/
build/
"@ | Out-File -FilePath .gitignore -Encoding UTF8
} else {
    Write-Host ".gitignore already exists — leaving as-is."
}

# Stage changes
Write-Host "Staging files..."
git add --all || Write-ErrorAndExit "git add failed."

# Commit
$hasCommits = git rev-parse --verify HEAD > $null 2>&1; if ($LASTEXITCODE -ne 0) { $hasCommits = $false } else { $hasCommits = $true }

if (-not $hasCommits) {
    Write-Host "Creating initial commit..."
    git commit -m $CommitMessage || Write-Host "No changes to commit or commit failed." -ForegroundColor Yellow
} else {
    Write-Host "Repository already has commits — making a new commit if there are staged changes..."
    git commit -m $CommitMessage || Write-Host "No staged changes to commit." -ForegroundColor Yellow
}

# Set branch name
Write-Host "Setting branch to '$Branch'..."
git branch -M $Branch || Write-ErrorAndExit "Failed to set branch to $Branch."

# Add or update remote (HTTPS without token)
$remoteExists = git remote | Select-String -Pattern "^origin$" -Quiet
if ($remoteExists) {
    if ($ForceRemote) {
        Write-Host "Updating existing 'origin' remote to $RemoteUrl..."
        git remote set-url origin $RemoteUrl || Write-ErrorAndExit "Failed to set remote URL."
    } else {
        Write-Host "Remote 'origin' already exists. Use -ForceRemote to overwrite it. Current remote: $(git remote get-url origin)"
    }
} else {
    Write-Host "Adding remote origin: $RemoteUrl"
    git remote add origin $RemoteUrl || Write-ErrorAndExit "Failed to add remote origin."
}

# Prompt for GitHub credentials securely
$GitUser = Read-Host "GitHub username (leave blank to use current Windows username)"
if ([string]::IsNullOrWhiteSpace($GitUser)) { $GitUser = $env:USERNAME }

Write-Host "Enter your GitHub Personal Access Token (PAT) with 'repo' scope. It will not be stored on disk permanently." -ForegroundColor Yellow
$secureToken = Read-Host "Personal Access Token (input hidden)" -AsSecureString

# Convert SecureString to plain text in memory (cleared shortly after use)
$ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($secureToken)
$plainToken = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($ptr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($ptr)

# Create a temporary askpass helper (ephemeral). Git will call this program with the prompt text.
$askpassPath = Join-Path $env:TEMP ("git-askpass-" + [System.Guid]::NewGuid().ToString() + ".cmd")

$askpassContent = @"
@echo off
REM Temporary git askpass helper. This file is removed after use.
setlocal ENABLEDELAYEDEXPANSION
set prompt=%1
echo %prompt% | findstr /I "username" >nul
if %errorlevel%==0 (
  echo %GIT_USER%
) else (
  echo %GIT_PASS%
)
endlocal
"@  

# Write the askpass helper while injecting credentials via environment variables (NOT writing secrets into the file contents)
$askpassContent | Out-File -FilePath $askpassPath -Encoding ASCII

# Make the temporary askpass executable by Git (it will run the .cmd)
# Set environment variables that the helper will read; these are not persisted to disk.
$env:GIT_ASKPASS = $askpassPath
$env:GIT_TERMINAL_PROMPT = "0"
$env:GIT_USER = $GitUser
$env:GIT_PASS = $plainToken

Write-Host "Pushing to origin/$Branch using secure prompt helper..." -ForegroundColor Cyan

try {
    # Run the push with environment configured so git will call the temporary askpass helper
git push -u origin $Branch
} catch {
    Write-Host "Push failed. Error: $_" -ForegroundColor Red
    # Clean up environment and file before exiting
    Remove-Item -Path $askpassPath -ErrorAction SilentlyContinue
    $env:GIT_ASKPASS = $null
    $env:GIT_TERMINAL_PROMPT = $null
    $env:GIT_USER = $null
    $env:GIT_PASS = $null
    $plainToken = $null
    exit 2
}

# Clean up: remove temporary helper and clear sensitive variables
Remove-Item -Path $askpassPath -ErrorAction SilentlyContinue
$env:GIT_ASKPASS = $null
$env:GIT_TERMINAL_PROMPT = $null
$env:GIT_USER = $null
$env:GIT_PASS = $null
$plainToken = $null

Write-Host "Done. Repository pushed to $RemoteUrl" -ForegroundColor Green

Write-Host "\nNotes:\n- The PAT was never embedded in the remote URL or command history.\n- A temporary askpass helper was created in $env:TEMP and removed after pushing.\n- If push failed due to permissions, confirm the token has 'repo' scope and that the remote URL is correct." -ForegroundColor Cyan
