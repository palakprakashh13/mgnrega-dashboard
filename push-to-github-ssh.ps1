param(
    [string]$RepoOwner = "palakprakashh13",
    [string]$RepoName = "mgnrega-dashboard",
    [string]$RemoteSshUrl = "",
    [string]$CommitMessage = "Initial commit: MGNREGA Dashboard",
    [string]$Branch = "main",
    [switch]$ForceRemote,
    [switch]$GenerateKey
)

function Write-ErrorAndExit {
    param([string]$Msg)
    Write-Host "ERROR: $Msg" -ForegroundColor Red
    exit 1
}

Write-Host "push-to-github-ssh.ps1 — push local project to GitHub using SSH" -ForegroundColor Cyan

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-ErrorAndExit "Git is not installed or not in PATH. Install Git and re-run this script."
}

if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
    Write-Host "Warning: ssh-keygen not found. SSH key generation won't be available." -ForegroundColor Yellow
}

# Determine SSH remote URL
if ([string]::IsNullOrWhiteSpace($RemoteSshUrl)) {
    $RemoteSshUrl = "git@github.com:$RepoOwner/$RepoName.git"
}

$sshDir = Join-Path $env:USERPROFILE ".ssh"
$idEd25519 = Join-Path $sshDir "id_ed25519"
$pubKeyPath = "$idEd25519.pub"

# Generate SSH key if requested or missing
if ($GenerateKey -or -not (Test-Path $idEd25519)) {
    if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit "ssh-keygen not available. Install OpenSSH client (Windows Feature) or run this on a system with ssh-keygen."
    }

    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    Write-Host "Generating an ed25519 SSH key pair at $idEd25519 (no passphrase)" -ForegroundColor Green
    ssh-keygen -t ed25519 -f $idEd25519 -N "" -C "${env:USERNAME}@$(hostname)-mgnrega" || Write-ErrorAndExit "ssh-keygen failed."
}

if (-not (Test-Path $pubKeyPath)) {
    Write-Host "No public key found at $pubKeyPath. Run the script with -GenerateKey or create an SSH key manually." -ForegroundColor Yellow
} else {
    Write-Host "
Your public SSH key (copy the whole block below and add to GitHub -> Settings -> SSH and GPG keys -> New SSH key):" -ForegroundColor Cyan
    Get-Content $pubKeyPath
    Write-Host "\nPress Enter after you've added the key to GitHub (or Ctrl+C to abort)." -ForegroundColor Yellow
    Read-Host | Out-Null
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

# Add or update remote (SSH)
$remoteExists = git remote | Select-String -Pattern "^origin$" -Quiet
if ($remoteExists) {
    if ($ForceRemote) {
        Write-Host "Updating existing 'origin' remote to $RemoteSshUrl..."
        git remote set-url origin $RemoteSshUrl || Write-ErrorAndExit "Failed to set remote URL."
    } else {
        Write-Host "Remote 'origin' already exists. Use -ForceRemote to overwrite it. Current remote: $(git remote get-url origin)"
    }
} else {
    Write-Host "Adding remote origin: $RemoteSshUrl"
    git remote add origin $RemoteSshUrl || Write-ErrorAndExit "Failed to add remote origin."
}

# Test SSH connection
Write-Host "Testing SSH connection to GitHub..." -ForegroundColor Cyan
try {
    ssh -T git@github.com 2>&1 | ForEach-Object { Write-Host $_ }
} catch {
    Write-Host "SSH test failed; ensure your public key is added to GitHub and the SSH agent/key is available." -ForegroundColor Yellow
}

# Push
Write-Host "Pushing to origin/$Branch..."
try {
    git push -u origin $Branch
} catch {
    Write-Host "Push failed. If permission denied, ensure SSH key is correctly added and agent is running." -ForegroundColor Red
    exit 2
}

Write-Host "Done. Repository pushed via SSH to $RemoteSshUrl" -ForegroundColor Green

Write-Host "\nNext: Use 'git status' and 'git remote -v' to verify. For repeated use, add your key to ssh-agent: `ssh-add $idEd25519`" -ForegroundColor Cyan
