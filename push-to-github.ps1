param(
    [string]$RepoOwner = "palakprakashh13",
    [string]$RepoName = "mgnrega-dashboard",
    [string]$RemoteUrl = "",
    [string]$CommitMessage = "Initial commit: MGNREGA Dashboard",
    [string]$Branch = "main",
    [switch]$ForceRemote,
    [switch]$UseToken,
    [string]$Token
)

function Write-ErrorAndExit {
    param([string]$Msg)
    Write-Host "ERROR: $Msg" -ForegroundColor Red
    exit 1
}

Write-Host "push-to-github.ps1 — push local project to GitHub" -ForegroundColor Cyan

# Ensure git is available
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-ErrorAndExit "Git is not installed or not in PATH. Install Git and re-run this script."
}

# Determine remote url
if ([string]::IsNullOrWhiteSpace($RemoteUrl)) {
    $RemoteUrl = "https://github.com/$RepoOwner/$RepoName.git"
}

# Optionally embed token (warning)
if ($UseToken -and -not [string]::IsNullOrWhiteSpace($Token)) {
    Write-Host "Using token-authenticated remote URL (token will be embedded in the remote URL)." -ForegroundColor Yellow
    $escapedToken = [System.Uri]::EscapeDataString($Token)
    $RemoteUrlWithToken = $RemoteUrl -replace '^https://', "https://$escapedToken@"
} else {
    $RemoteUrlWithToken = $RemoteUrl
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

# Add or update remote
$remoteExists = git remote | Select-String -Pattern "^origin$" -Quiet
if ($remoteExists) {
    if ($ForceRemote) {
        Write-Host "Updating existing 'origin' remote to $RemoteUrlWithToken..."
        git remote set-url origin $RemoteUrlWithToken || Write-ErrorAndExit "Failed to set remote URL."
    } else {
        Write-Host "Remote 'origin' already exists. Use -ForceRemote to overwrite it. Current remote: $(git remote get-url origin)"
    }
} else {
    Write-Host "Adding remote origin: $RemoteUrlWithToken"
    git remote add origin $RemoteUrlWithToken || Write-ErrorAndExit "Failed to add remote origin."
}

# Push
Write-Host "Pushing to origin/$Branch..."
$pushCmd = "git push -u origin $Branch"
try {
    iex $pushCmd
} catch {
    Write-Host "Push failed. If using HTTPS you may be prompted for credentials, or consider using a personal access token with -UseToken.`nError: $_" -ForegroundColor Red
    exit 2
}

Write-Host "Done. Repository pushed to $RemoteUrl" -ForegroundColor Green

# Helpful follow-up instructions
Write-Host "
Next steps:
- If push failed due to authentication, create a personal access token and re-run with -UseToken -Token <PAT>, or set up SSH keys and add an SSH remote URL.
- To clone: git clone $RemoteUrl
" -ForegroundColor Cyan
