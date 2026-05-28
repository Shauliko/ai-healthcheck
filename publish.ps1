# publish.ps1 - one-shot publish + verify for ai-healthcheck.
# Idempotent: stops at the first failure with a clear message; re-run after fixing.
#
# Usage (from anywhere):
#   cd C:\dev\ai-healthcheck
#   .\publish.ps1
#
# Or with PowerShell execution policy bypass (if you get blocked):
#   PowerShell -ExecutionPolicy Bypass -File .\publish.ps1

$ErrorActionPreference = 'Stop'
$REPO_ROOT = 'C:\dev\ai-healthcheck'
$PKG_NAME  = 'ai-healthcheck'
$TARGET_VERSION = '0.1.0'

function Section($n, $title) {
    Write-Host ""
    Write-Host "=== [$n] $title ===" -ForegroundColor Cyan
}
function Pass($msg)   { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Warn($msg)   { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Info($msg)   { Write-Host "  $msg" }
function Fail($msg)   {
    Write-Host ""
    Write-Host "  [STOP] $msg" -ForegroundColor Red
    Write-Host ""
    Write-Host "Fix the above, then re-run .\publish.ps1" -ForegroundColor Red
    exit 1
}
function Ask($prompt, $default = '') {
    if ($default) { $reply = Read-Host "$prompt [$default]" } else { $reply = Read-Host $prompt }
    if ([string]::IsNullOrWhiteSpace($reply)) { return $default }
    return $reply
}
function YesNo($prompt) {
    $r = Read-Host "$prompt (y/N)"
    return ($r -eq 'y' -or $r -eq 'Y')
}

# ----------------------------------------------------------------------
# Step 0 - verify location
# ----------------------------------------------------------------------
Section 0 "Verify repo location"
if (-not (Test-Path $REPO_ROOT)) { Fail "$REPO_ROOT does not exist" }
Set-Location $REPO_ROOT
if (-not (Test-Path .\package.json)) { Fail "No package.json in $REPO_ROOT" }
if (-not (Test-Path .\bin\cli.js)) { Fail "No bin/cli.js (corrupt repo?)" }
Pass "Repo at $REPO_ROOT"

# ----------------------------------------------------------------------
# Step 1 - verify code-side fixes are present
# ----------------------------------------------------------------------
Section 1 "Verify code fixes"
$pkg = Get-Content .\package.json -Raw | ConvertFrom-Json

# 1a: version
if ($pkg.version -ne $TARGET_VERSION) {
    Warn "version is '$($pkg.version)', expected '$TARGET_VERSION'"
    if (YesNo "  Reset version to $TARGET_VERSION?") {
        & npm pkg set "version=$TARGET_VERSION" | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "npm pkg set version failed" }
        Pass "version reset to $TARGET_VERSION"
        $pkg = Get-Content .\package.json -Raw | ConvertFrom-Json
    } else {
        Fail "Wrong version. Run: npm pkg set version=$TARGET_VERSION"
    }
} else {
    Pass "version = $TARGET_VERSION"
}

# 1b: bin path (no ./ prefix - npm strips entries with ./)
$binValue = $pkg.bin.$PKG_NAME
if (-not $binValue) { Fail "package.json missing bin.$PKG_NAME" }
if ($binValue -match '^\.[/\\]') {
    Warn "bin path has './' prefix - npm will strip it on publish"
    if (YesNo "  Fix to 'bin/cli.js'?") {
        & npm pkg set "bin.$PKG_NAME=bin/cli.js" | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "npm pkg set bin failed" }
        Pass "bin path fixed"
    } else { Fail "bin path must not start with ./" }
} else {
    Pass "bin path = $binValue (no ./ prefix)"
}

# 1c: env-util.js exists (Windows env fix)
if (-not (Test-Path .\src\env-util.js)) {
    Fail "src/env-util.js missing - the Windows env fix isn't in. Re-pull the repo."
}
Pass "src/env-util.js present"

# 1d: env_present.js uses envGet (not raw process.env spread)
$envText = Get-Content .\src\checks\env_present.js -Raw
if ($envText -match '\{\s*\.\.\.process\.env\s*\}') {
    Fail "src/checks/env_present.js still spreads process.env - the Windows fix isn't in."
}
if ($envText -notmatch "from '../env-util.js'") {
    Fail "src/checks/env_present.js doesn't import envGet"
}
Pass "env_present.js uses envGet helper"

# ----------------------------------------------------------------------
# Step 2 - GitHub username / replace YOUR-USER
# ----------------------------------------------------------------------
Section 2 "GitHub username and YOUR-USER replacement"
$readmeText = Get-Content .\README.md -Raw
$pkgText    = Get-Content .\package.json -Raw
$hasPlaceholder = ($readmeText -match 'YOUR-USER') -or ($pkgText -match 'YOUR-USER')

if ($hasPlaceholder) {
    Info "Found YOUR-USER placeholders. Need your GitHub username."
    $ghUser = Ask "  GitHub username"
    if ([string]::IsNullOrWhiteSpace($ghUser)) { Fail "GitHub username required" }
    if ($ghUser -match '[^a-zA-Z0-9-_]') { Fail "Invalid GitHub username: $ghUser" }

    # package.json
    $newPkg = $pkgText -replace 'YOUR-USER', $ghUser
    Set-Content -Path .\package.json -Value $newPkg -NoNewline -Encoding UTF8
    # README
    $newReadme = $readmeText -replace 'YOUR-USER', $ghUser
    Set-Content -Path .\README.md -Value $newReadme -NoNewline -Encoding UTF8

    Pass "Replaced YOUR-USER -> $ghUser in package.json and README.md"
    $pkg = Get-Content .\package.json -Raw | ConvertFrom-Json
} else {
    # try to recover username from existing package.json
    if ($pkg.homepage -match 'github\.com/([^/]+)/') { $ghUser = $matches[1] }
    elseif ($pkg.repository.url -match 'github\.com/([^/]+)/') { $ghUser = $matches[1] }
    else { $ghUser = '(unknown)' }
    Pass "No YOUR-USER placeholders. Detected username: $ghUser"
}

# ----------------------------------------------------------------------
# Step 3 - author field
# ----------------------------------------------------------------------
Section 3 "Author field"
$pkg = Get-Content .\package.json -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($pkg.author)) {
    $defaultAuthor = 'Saul Eini <eini.shaul@gmail.com>'
    $authorIn = Ask "  Author string" $defaultAuthor
    & npm pkg set "author=$authorIn" | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "npm pkg set author failed" }
    Pass "author set to: $authorIn"
} else {
    Pass "author already set: $($pkg.author)"
}

# ----------------------------------------------------------------------
# Step 4 - run tests
# ----------------------------------------------------------------------
Section 4 "Run tests (expect 11/11)"
$testOut = & node --test 'test/*.test.js' 2>&1 | Out-String
Write-Host $testOut
if ($LASTEXITCODE -ne 0) { Fail "Tests failed - see output above" }
if ($testOut -notmatch '# pass 11') {
    Fail "Expected '# pass 11' in test output. See above."
}
if ($testOut -match '# fail [^0]') { Fail "One or more tests failed" }
Pass "All 11 tests passed"

# ----------------------------------------------------------------------
# Step 5 - dry-run publish, check for warnings
# ----------------------------------------------------------------------
Section 5 "npm publish --dry-run (sanity check)"
$dryOut = (& npm publish --dry-run --access public 2>&1 | Out-String)
Write-Host $dryOut

# Filter out known-safe warnings
$badLines = @()
foreach ($line in ($dryOut -split "`r?`n")) {
    if ($line -match 'warn' -and
        $line -notmatch 'requires you to be logged in' -and
        $line -notmatch 'package-lock\.json' -and
        $line -notmatch 'lockfile') {
        $badLines += $line
    }
    if ($line -match 'error' -and $line -notmatch 'E404') {
        $badLines += $line
    }
}
if ($badLines.Count -gt 0) {
    Warn "Unexpected publish-time warnings/errors:"
    foreach ($l in $badLines) { Warn "    $l" }
    if (-not (YesNo "  Continue anyway?")) { Fail "Aborted on dry-run warnings" }
} else {
    Pass "Dry-run clean (only login warning is expected at this step)"
}

# ----------------------------------------------------------------------
# Step 6 - npm login check
# ----------------------------------------------------------------------
Section 6 "Check npm login"
$whoami = (& npm whoami 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $whoami -match 'ENEEDAUTH|requires you to be logged in') {
    Warn "Not logged into npm."
    Info "Need to run 'npm login' - this opens a browser. Complete it and come back."
    if (YesNo "  Run 'npm login' now?") {
        & npm login
        if ($LASTEXITCODE -ne 0) { Fail "npm login failed - run it manually then re-run this script" }
        $whoami = (& npm whoami 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { Fail "Still not logged in after npm login" }
    } else {
        Fail "Login required. Run: npm login"
    }
}
Pass "Logged in as: $whoami"

# Optional 2FA check
$profileOut = (& npm profile get 2>&1 | Out-String)
if ($profileOut -match 'two-factor.*disabled') {
    Warn "npm 2FA is disabled. Recommended for publish-able accounts."
} elseif ($profileOut -match 'two-factor') {
    Pass "npm 2FA appears enabled"
}

# ----------------------------------------------------------------------
# Step 7 - THE REAL PUBLISH
# ----------------------------------------------------------------------
Section 7 "Publish to npm (this is the real one)"
Info "About to publish: $PKG_NAME@$($pkg.version)"
Info "Registry:         https://registry.npmjs.org/"
Info "Access:           public"
Write-Host ""
if (-not (YesNo "  PROCEED with real publish?")) { Fail "Aborted by user" }

$publishOut = (& npm publish --access public 2>&1 | Out-String)
Write-Host $publishOut
if ($LASTEXITCODE -ne 0) {
    if ($publishOut -match 'E404') {
        Fail "404 from registry. You're likely not logged in (re-run 'npm login') or 2FA timed out."
    }
    if ($publishOut -match 'EPUBLISHCONFLICT|already published|cannot publish over') {
        Fail "Version $($pkg.version) already exists on npm. Bump version: npm version patch"
    }
    Fail "npm publish failed - see output above"
}
if ($publishOut -notmatch "\+ $PKG_NAME@") {
    Fail "Expected '+ $PKG_NAME@<version>' in output. Publish may have failed silently."
}
Pass "Published $PKG_NAME@$($pkg.version)"

# ----------------------------------------------------------------------
# Step 8 - smoke test from clean dir
# ----------------------------------------------------------------------
Section 8 "Smoke test the published version from a clean directory"
$smokeDir = Join-Path $env:TEMP "aih-smoke-$([guid]::NewGuid().ToString().Substring(0,8))"
New-Item -ItemType Directory -Path $smokeDir | Out-Null
Push-Location $smokeDir
try {
    Info "Smoke dir: $smokeDir"
    Info "Waiting 8 seconds for registry to propagate..."
    Start-Sleep -Seconds 8

    # 8a: --version
    Info "-> npx -y $PKG_NAME@latest --version"
    $verOut = (& npx -y "$PKG_NAME@latest" --version 2>&1 | Out-String).Trim()
    Write-Host "   $verOut"
    if ($LASTEXITCODE -ne 0) { Fail "npx --version failed" }
    if ($verOut -notmatch [regex]::Escape($TARGET_VERSION)) {
        Fail "Expected $TARGET_VERSION, got: $verOut (try re-running this script in 30s - registry can be slow)"
    }
    Pass "Version reports $verOut"

    # 8b: init
    Info "-> npx -y $PKG_NAME@latest init"
    & npx -y "$PKG_NAME@latest" init
    if ($LASTEXITCODE -ne 0) { Fail "init failed" }
    if (-not (Test-Path .\healthcheck.config.yaml)) { Fail "init didn't write config" }
    Pass "init wrote healthcheck.config.yaml"

    # 8c: run --ai-json (will fail some checks against example.com - that's expected)
    Info "-> npx -y $PKG_NAME@latest run --ai-json (failures expected on example.com)"
    & npx -y "$PKG_NAME@latest" run --ai-json
    # exit code may be 1 due to fails - don't gate on it
    if (-not (Test-Path .\ai-healthcheck.ai.json)) { Fail "run didn't write ai-json" }
    Pass "run wrote ai-healthcheck.ai.json"

    # 8d: sanity on JSON structure
    $aiJson = Get-Content .\ai-healthcheck.ai.json -Raw | ConvertFrom-Json
    if (-not $aiJson.instructions_for_ai) { Fail "ai.json missing instructions_for_ai" }
    if (-not $aiJson.questions_to_investigate) { Fail "ai.json missing questions_to_investigate" }
    if (-not $aiJson.schema_notes) { Fail "ai.json missing schema_notes" }
    Pass "AI JSON has instructions_for_ai + questions_to_investigate + schema_notes"
} finally {
    Pop-Location
    Remove-Item -Recurse -Force $smokeDir -ErrorAction SilentlyContinue
}

# ----------------------------------------------------------------------
# Step 9 - git commit + tag (optional)
# ----------------------------------------------------------------------
Section 9 "Git: commit fixes, tag $TARGET_VERSION, push"
Set-Location $REPO_ROOT

$gitInside = (& git rev-parse --is-inside-work-tree 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $gitInside -ne 'true') {
    Warn "Not a git repo. Skipping git steps. To initialize:"
    Info "    git init"
    Info "    git remote add origin https://github.com/$ghUser/$PKG_NAME.git"
} else {
    $status = (& git status --porcelain 2>&1 | Out-String).Trim()
    if ($status) {
        Info "Uncommitted changes detected. Committing..."
        & git add -A | Out-Null
        & git commit -m "v${TARGET_VERSION}: fix bin field, fix Windows env lookup, replace placeholders" | Out-Null
        if ($LASTEXITCODE -ne 0) { Warn "git commit returned non-zero (might be 'nothing to commit')" }
        else { Pass "Committed" }
    } else {
        Pass "No uncommitted changes"
    }

    $existingTag = (& git tag --list "v$TARGET_VERSION" 2>&1 | Out-String).Trim()
    if (-not $existingTag) {
        & git tag "v$TARGET_VERSION" | Out-Null
        if ($LASTEXITCODE -eq 0) { Pass "Tagged v$TARGET_VERSION" }
        else { Warn "git tag returned non-zero" }
    } else {
        Pass "Tag v$TARGET_VERSION already exists"
    }

    $remote = (& git remote 2>&1 | Out-String).Trim()
    if ($remote) {
        if (YesNo "  Push to remote ($remote)?") {
            & git push 2>&1 | Write-Host
            & git push --tags 2>&1 | Write-Host
            Pass "Pushed"
        }
    } else {
        Warn "No git remote configured. Add with:"
        Info "    git remote add origin https://github.com/$ghUser/$PKG_NAME.git"
        Info "    git push -u origin main"
        Info "    git push --tags"
    }
}

# ----------------------------------------------------------------------
# DONE
# ----------------------------------------------------------------------
Write-Host ""
Write-Host "===================================================" -ForegroundColor Green
Write-Host " SHIPPED." -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Green
Write-Host " npm:    https://www.npmjs.com/package/$PKG_NAME"
Write-Host " GitHub: https://github.com/$ghUser/$PKG_NAME"
Write-Host ""
Write-Host " Next:"
Write-Host "   1. Run the §6 positioning A/B test (DM 3 friends)"
Write-Host "   2. Record the screencap (script in chat above)"
Write-Host "   3. Submit HN with your winning title (URL: GitHub repo, not npm)"
Write-Host ""
