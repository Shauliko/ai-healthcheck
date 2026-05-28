# ship.ps1 -- full preflight + publish for ai-healthcheck.
# Single self-contained command. Detects what's missing, auto-fixes what it can,
# prompts only for what requires human input, then publishes.
#
# Usage:
#   cd C:\dev\ai-healthcheck
#   .\ship.ps1
#
# If PowerShell execution policy blocks it:
#   PowerShell -ExecutionPolicy Bypass -File .\ship.ps1
#
# Every phase is idempotent. If something fails, fix it and re-run.

# Continue on errors - we check $LASTEXITCODE explicitly after every native command.
# 'Stop' causes PowerShell to treat npm's stderr ('npm notice ...') as a fatal error
# even when npm exits 0.
$ErrorActionPreference = 'Continue'
# PS 7.3+: prevent native commands' stderr from being elevated to errors.
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $PSNativeCommandUseErrorActionPreference = $false
}
$REPO_ROOT      = 'C:\dev\ai-healthcheck'
$PKG_NAME       = 'ai-healthcheck'
$TARGET_VERSION = '0.1.0'
$REQUIRED_NODE  = 18
$REGISTRY       = 'https://registry.npmjs.org'

# ----- helpers -----
function Phase($n, $title) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor DarkGray
    Write-Host (" Phase {0}: {1}" -f $n, $title) -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor DarkGray
}
function CheckOK($msg)   { Write-Host "  [PASS] $msg" -ForegroundColor Green }
function CheckWarn($msg) { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function CheckInfo($msg) { Write-Host "         $msg" -ForegroundColor Gray }
function Stop_($msg) {
    Write-Host ""
    Write-Host "  [STOP] $msg" -ForegroundColor Red
    Write-Host ""
    Write-Host " Fix the above, then re-run .\ship.ps1" -ForegroundColor Red
    Write-Host " Done steps are skipped on re-run." -ForegroundColor Gray
    exit 1
}

function Show-NpmLogTail {
    # Find the most recent npm debug log and print the last N lines + diagnose common errors.
    $logDir = Join-Path $env:LOCALAPPDATA "npm-cache\_logs"
    if (-not (Test-Path $logDir)) { return $null }
    $latest = Get-ChildItem $logDir -Filter "*-debug-*.log" -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { return $null }
    Write-Host ""
    Write-Host "  --- last 30 lines of npm log ($($latest.Name)) ---" -ForegroundColor Yellow
    Get-Content $latest.FullName -Tail 30 | ForEach-Object {
        Write-Host "  | $_" -ForegroundColor Gray
    }
    Write-Host "  --- end log ---" -ForegroundColor Yellow

    # Diagnose
    $content = Get-Content $latest.FullName -Raw
    Write-Host ""
    if ($content -match "EOTP|otp |one-time password|OTP required") {
        Write-Host "  DIAGNOSIS: npm requires a 2FA OTP." -ForegroundColor Yellow
        Write-Host "  FIX:       Re-run with: npm publish --access public --otp=YOUR_6_DIGIT_CODE" -ForegroundColor Yellow
        Write-Host "             (Open your authenticator app, copy current 6-digit code, paste it after --otp=)" -ForegroundColor Yellow
        return "EOTP"
    } elseif ($content -match "E401|ENEEDAUTH") {
        Write-Host "  DIAGNOSIS: Not authenticated to npm registry." -ForegroundColor Yellow
        Write-Host "  FIX:       Run: npm login   then re-run .\ship.ps1" -ForegroundColor Yellow
        return "EAUTH"
    } elseif ($content -match "EPUBLISHCONFLICT|cannot publish over") {
        Write-Host "  DIAGNOSIS: This version is already published to npm." -ForegroundColor Yellow
        Write-Host "  FIX:       npm version patch   then re-run .\ship.ps1" -ForegroundColor Yellow
        return "ECONFLICT"
    } elseif ($content -match "E403") {
        Write-Host "  DIAGNOSIS: Forbidden (403). Most likely: 2FA OTP required, OR you do not own this name." -ForegroundColor Yellow
        Write-Host "  FIX:       Try: npm publish --access public --otp=YOUR_6_DIGIT_CODE" -ForegroundColor Yellow
        Write-Host "             If that does not work, the name may have been claimed - check: npm view $PKG_NAME" -ForegroundColor Yellow
        return "E403"
    } elseif ($content -match "ENOTFOUND|getaddrinfo") {
        Write-Host "  DIAGNOSIS: Cannot resolve registry hostname (network/DNS issue)." -ForegroundColor Yellow
        return "ENETWORK"
    } elseif ($content -match "ETIMEDOUT|ECONNREFUSED|ECONNRESET") {
        Write-Host "  DIAGNOSIS: Network connection to registry failed." -ForegroundColor Yellow
        return "ENETWORK"
    } elseif ($content -match "EACCES|EPERM") {
        Write-Host "  DIAGNOSIS: Permission denied. Probably a file lock or filesystem issue." -ForegroundColor Yellow
        return "EACCES"
    }
    return "UNKNOWN"
}

function Ask($prompt, $default = '') {
    if ($default) {
        $reply = Read-Host "  > $prompt [$default]"
        if ([string]::IsNullOrWhiteSpace($reply)) { return $default }
        return $reply
    }
    return (Read-Host "  > $prompt")
}
function YesNo($prompt, $default = 'n') {
    $hint = if ($default -eq 'y') { '(Y/n)' } else { '(y/N)' }
    $reply = Read-Host "  > $prompt $hint"
    if ([string]::IsNullOrWhiteSpace($reply)) { return ($default -eq 'y') }
    return ($reply -match '^[yY]')
}

# ============================================================
# PHASE 1: SYSTEM AUDIT
# ============================================================
Phase 1 "System audit"

$psVer = $PSVersionTable.PSVersion
if ($psVer.Major -lt 5) { Stop_ "PowerShell 5.1+ required (you have $psVer)" }
CheckOK "PowerShell $psVer"

try {
    $nodeVer = (& node --version 2>&1).Trim() -replace '^v',''
    if (-not $nodeVer) { throw "no output" }
} catch { Stop_ "Node.js not found. Install from https://nodejs.org/" }
$nodeMajor = [int]($nodeVer -split '\.')[0]
if ($nodeMajor -lt $REQUIRED_NODE) {
    Stop_ "Node $REQUIRED_NODE+ required (you have v$nodeVer). Upgrade from https://nodejs.org/"
}
CheckOK "Node v$nodeVer"

try {
    $npmVer = (& npm --version 2>&1).Trim()
    if (-not $npmVer) { throw "no output" }
} catch { Stop_ "npm not found (should ship with Node)" }
CheckOK "npm $npmVer"

$script:HAS_GIT = $false
try {
    $gitVer = (& git --version 2>&1).Trim()
    if ($gitVer -match 'git version') { $script:HAS_GIT = $true; CheckOK $gitVer }
} catch {}
if (-not $script:HAS_GIT) { CheckWarn "git not found - git steps will be skipped" }

try {
    $resp = Invoke-WebRequest -Uri "$REGISTRY/-/ping" -Method GET -TimeoutSec 10 -UseBasicParsing
    if ($resp.StatusCode -ne 200) { Stop_ "npm registry HTTP $($resp.StatusCode)" }
    CheckOK "npm registry reachable"
} catch {
    Stop_ "Cannot reach npm registry: $($_.Exception.Message)"
}

# ============================================================
# PHASE 2: NPM AUTH
# ============================================================
Phase 2 "npm auth"

$whoami = (& npm whoami 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $whoami -match 'ENEEDAUTH|requires you to be logged in|404') {
    CheckWarn "Not logged into npm"
    CheckInfo "Running 'npm login' opens a browser. Complete login then script resumes."
    if (YesNo "Run 'npm login' now?" 'y') {
        & npm login
        if ($LASTEXITCODE -ne 0) { Stop_ "npm login failed" }
        $whoami = (& npm whoami 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { Stop_ "Still not logged in" }
    } else {
        Stop_ "Login required to publish"
    }
}
CheckOK "Logged in as: $whoami"

$profileOut = (& npm profile get 2>&1 | Out-String)
if ($profileOut -match 'two-factor.*disabled') {
    CheckWarn "npm 2FA disabled (recommended for publishers)"
} elseif ($profileOut -match 'two-factor') {
    CheckOK "npm 2FA enabled"
}

# ============================================================
# PHASE 3: REPO INTEGRITY
# ============================================================
Phase 3 "Repo integrity"

if (-not (Test-Path $REPO_ROOT)) { Stop_ "$REPO_ROOT does not exist" }
Set-Location $REPO_ROOT
CheckOK "Repo at $REPO_ROOT"

$required = @(
    'package.json','README.md','LICENSE',
    'bin\cli.js',
    'src\runner.js','src\config.js','src\index.js','src\env-util.js',
    'src\output\ai-json.js','src\output\json.js','src\output\terminal.js',
    'src\commands\run.js','src\commands\init.js',
    'src\checks\index.js','src\checks\http.js','src\checks\env_present.js',
    'src\checks\ssl_expiry.js','src\checks\stripe_key.js',
    'examples\nextjs-supabase-stripe.yaml','examples\vercel-static.yaml',
    'test\smoke.test.js'
)
$missing = @($required | Where-Object { -not (Test-Path $_) })
if ($missing.Count -gt 0) {
    foreach ($m in $missing) { CheckWarn "Missing: $m" }
    Stop_ "Required files missing - repo incomplete"
}
CheckOK "All required files present ($($required.Count) files)"

# Mojibake detection (ASCII-safe: byte-level scan).
# Double-encoded UTF-8 starts with 0xC3 0xA2 (the '\xC3\xA2' bigram of most reencoded high-bit chars).
$readmeBytes = [System.IO.File]::ReadAllBytes((Resolve-Path '.\README.md'))
$mojibakeFound = $false
for ($i = 0; $i -lt ($readmeBytes.Length - 1); $i++) {
    if ($readmeBytes[$i] -eq 0xC3 -and $readmeBytes[$i+1] -eq 0xA2) {
        $mojibakeFound = $true
        break
    }
}
if ($mojibakeFound) {
    Stop_ "README contains 0xC3 0xA2 byte sequence (double-encoded UTF-8). Restore README from git or re-pull."
}
$nonAsciiCount = ($readmeBytes | Where-Object { $_ -gt 127 }).Count
if ($nonAsciiCount -gt 0) {
    CheckWarn "README has $nonAsciiCount non-ASCII bytes - probably fine, but watch for rendering issues on npm"
} else {
    CheckOK "README is pure ASCII (immune to mojibake)"
}

try {
    $pkg = Get-Content .\package.json -Raw | ConvertFrom-Json
} catch {
    Stop_ "package.json invalid JSON: $($_.Exception.Message)"
}
CheckOK "package.json valid JSON"

if (-not (Test-Path .\node_modules)) {
    CheckWarn "node_modules missing - running 'npm install'..."
    & npm install
    if ($LASTEXITCODE -ne 0) { Stop_ "npm install failed" }
    CheckOK "Dependencies installed"
} else {
    CheckOK "node_modules present"
}

# ============================================================
# PHASE 4: AUTO-FIX repo state
# ============================================================
Phase 4 "Auto-fix repo state"

# version
if ($pkg.version -ne $TARGET_VERSION) {
    CheckWarn "version is '$($pkg.version)', expected '$TARGET_VERSION'"
    if (YesNo "Reset to $TARGET_VERSION?" 'y') {
        & npm pkg set "version=$TARGET_VERSION" | Out-Null
        $pkg = Get-Content .\package.json -Raw | ConvertFrom-Json
        CheckOK "version reset"
    } else { Stop_ "Wrong version" }
} else {
    CheckOK "version = $TARGET_VERSION"
}

# bin path
$binValue = $pkg.bin.$PKG_NAME
if (-not $binValue) {
    if (YesNo "bin entry missing - set 'ai-healthcheck' -> 'bin/cli.js'?" 'y') {
        & npm pkg set "bin.$PKG_NAME=bin/cli.js" | Out-Null
        CheckOK "bin set"
    } else { Stop_ "bin required" }
} elseif ($binValue -match '^\.[/\\]') {
    CheckWarn "bin has './' prefix - npm strips it"
    if (YesNo "Fix to 'bin/cli.js'?" 'y') {
        & npm pkg set "bin.$PKG_NAME=bin/cli.js" | Out-Null
        CheckOK "bin path fixed"
    } else { Stop_ "bin path must not start with ./" }
} else {
    CheckOK "bin = $binValue"
}

# YOUR-USER placeholders
$pkgText = Get-Content .\package.json -Raw
$readmeText = Get-Content .\README.md -Raw
$hasPlaceholder = ($pkgText -match 'YOUR-USER') -or ($readmeText -match 'YOUR-USER')
$script:GH_USER = $null
if ($hasPlaceholder) {
    CheckWarn "YOUR-USER placeholders detected"
    $script:GH_USER = Ask "GitHub username"
    if ([string]::IsNullOrWhiteSpace($script:GH_USER)) { Stop_ "GitHub username required" }
    if ($script:GH_USER -match '[^a-zA-Z0-9-_]') { Stop_ "Invalid username (only a-zA-Z0-9-_)" }
    # Use [System.IO.File]::WriteAllText for atomic writes (Set-Content -NoNewline has
    # been seen to truncate mid-write). Validate JSON parses after each write.
    function Set-FileAtomic($path, $content) {
        $abs = (Resolve-Path $path).Path
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($abs, $content, $utf8NoBom)
    }
    $pkgRaw = Get-Content .\package.json -Raw
    $newPkg = $pkgRaw -replace 'YOUR-USER', $script:GH_USER
    Set-FileAtomic .\package.json $newPkg
    # Re-validate immediately - if Set-Content truncated, fail loud rather than silently
    try {
        $pkg = Get-Content .\package.json -Raw | ConvertFrom-Json
    } catch {
        Stop_ "package.json corrupted after YOUR-USER replacement: $($_.Exception.Message)"
    }
    $readmeRaw2 = Get-Content .\README.md -Raw
    $newReadme = $readmeRaw2 -replace 'YOUR-USER', $script:GH_USER
    Set-FileAtomic .\README.md $newReadme
    # Sanity: README should still contain the package name marker
    if (-not ((Get-Content .\README.md -Raw) -match '# ai-healthcheck')) {
        Stop_ "README corrupted after YOUR-USER replacement"
    }
    CheckOK "Replaced YOUR-USER -> $($script:GH_USER) (atomic write + JSON re-validated)"
} else {
    if ($pkg.homepage -match 'github\.com/([^/]+)/') { $script:GH_USER = $matches[1] }
    elseif ($pkg.repository.url -match 'github\.com/([^/]+)/') { $script:GH_USER = $matches[1] }
    else { $script:GH_USER = '(unknown)' }
    CheckOK "No placeholders. Detected username: $($script:GH_USER)"
}

# author
if ([string]::IsNullOrWhiteSpace($pkg.author)) {
    $defaultAuthor = 'Saul Eini <eini.shaul@gmail.com>'
    $authorIn = Ask "author" $defaultAuthor
    & npm pkg set "author=$authorIn" | Out-Null
    CheckOK "author set: $authorIn"
} else {
    CheckOK "author: $($pkg.author)"
}

# code-side: env_present uses envGet helper (Windows fix marker)
$envText = Get-Content .\src\checks\env_present.js -Raw
if ($envText -match '\{\s*\.\.\.process\.env\s*\}') {
    Stop_ "src/checks/env_present.js still spreads process.env (Windows env bug). Pull latest."
}
if ($envText -notmatch "from '../env-util.js'") {
    Stop_ "src/checks/env_present.js missing envGet import. Pull latest."
}
CheckOK "Windows env fix in place"

# ============================================================
# PHASE 5: TESTS
# ============================================================
Phase 5 "Tests"

# Force TAP reporter so output is consistent across Node versions / Windows terminals.
# Default spec reporter on Windows uses unicode symbols that mojibake in cp1252 consoles.
$testOut = (& node --test --test-reporter=tap 'test/*.test.js' 2>&1 | Out-String)
Write-Host $testOut
if ($LASTEXITCODE -ne 0) { Stop_ "Tests failed (node exit non-zero)" }
# Match 'pass 11' anywhere on a line, with or without TAP '#' prefix or spec-reporter symbol.
if ($testOut -notmatch '(?m)^[^a-zA-Z]*pass\s+11\b') {
    Stop_ "Expected 11 passing tests. Test output above did not match."
}
# Match 'fail N' where N is non-zero
if ($testOut -match '(?m)^[^a-zA-Z]*fail\s+[1-9]\d*\b') {
    Stop_ "One or more tests failed (see test output above)"
}
CheckOK "All 11 tests passed"

# ============================================================
# PHASE 6: DRY-RUN PUBLISH
# ============================================================
Phase 6 "npm publish --dry-run"

# Capture both streams. Wrap in try/catch as a belt-and-braces for unexpected stderr handling.
$dryOut = ''
try {
    $dryOut = (& npm publish --dry-run --access public 2>&1 | Out-String)
} catch {
    $dryOut = $_.ToString()
}
Write-Host $dryOut

$badLines = @()
foreach ($line in ($dryOut -split "`r?`n")) {
    if ($line -match 'warn' -and
        $line -notmatch 'requires you to be logged in' -and
        $line -notmatch 'package-lock\.json' -and
        $line -notmatch 'lockfile') {
        $badLines += $line.Trim()
    }
}
if ($badLines.Count -gt 0) {
    foreach ($l in $badLines) { CheckWarn $l }
    if (-not (YesNo "Continue despite warnings?")) { Stop_ "Aborted on dry-run warnings" }
} else {
    CheckOK "Dry-run clean"
}

# ============================================================
# PHASE 7: REAL PUBLISH
# ============================================================
Phase 7 "Publish (REAL)"

Write-Host ""
Write-Host "  About to publish: $PKG_NAME@$($pkg.version)" -ForegroundColor White
Write-Host "  Registry:         $REGISTRY" -ForegroundColor White
Write-Host "  Access:           public"
Write-Host "  Logged in as:     $whoami"
Write-Host ""
if (-not (YesNo "PROCEED with real publish?" 'n')) { Stop_ "Aborted by user" }

# npm requires 2FA OR a "bypass 2FA" token for publishing on registry.npmjs.org
# since 2024. This is enforced server-side regardless of your account 2FA setting.
#
# Two ways to satisfy npm:
#   A) Paste a 6-digit OTP from your authenticator app (requires 2FA set up on npm)
#   B) Paste a granular access token (recommended - 60-second setup, no OTPs ever)
#      Get one at: https://www.npmjs.com/settings/USER/tokens/granular-access-tokens
#      Settings: Read+Write, Bypass 2FA = YES, Packages = All
Write-Host ""
Write-Host "  npm publish requires either an OTP or a bypass-2FA token." -ForegroundColor White
Write-Host ""
Write-Host "  Paste ONE of these:" -ForegroundColor White
Write-Host "    - A 6-digit OTP from your authenticator (e.g. 123456)" -ForegroundColor Gray
Write-Host "    - A granular access token starting with 'npm_' (e.g. npm_xxxxxxxxxx)" -ForegroundColor Gray
Write-Host "    - Press Enter to try without (will likely fail with 403)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Need a token? 60-second setup:" -ForegroundColor Cyan
Write-Host "    1. Open: https://www.npmjs.com/settings/$($whoami)/tokens/granular-access-tokens" -ForegroundColor Cyan
Write-Host "    2. Generate New Token > Granular Access Token" -ForegroundColor Cyan
Write-Host "    3. Name=ship, Expiry=30 days, Permissions=Read+Write, Bypass 2FA=YES" -ForegroundColor Cyan
Write-Host "    4. Copy the token (starts with npm_) and paste it below" -ForegroundColor Cyan
Write-Host ""
$secret = Read-Host "  > OTP or token"

$otpArg = @()
$envTokenSet = $false
if ($secret -match '^npm_[A-Za-z0-9]{30,}$') {
    # Set token as env var for THIS npm process - it overrides any other auth.
    $env:NODE_AUTH_TOKEN = $secret
    $env:NPM_TOKEN = $secret
    # Also set in .npmrc temporarily via npm config for this session
    & npm config set "//registry.npmjs.org/:_authToken" $secret
    $envTokenSet = $true
    Write-Host "  Token registered (npm_${($secret.Substring(4,4))}****)" -ForegroundColor Cyan
} elseif ($secret -match '^\d{6,8}$') {
    $otpArg = @("--otp=$secret")
    Write-Host "  Will publish with --otp=$($secret.Substring(0,2))****" -ForegroundColor Cyan
} elseif ($secret) {
    Stop_ "Input must be a 6-digit OTP or a token starting with 'npm_'. Got: '$secret'"
} else {
    Write-Host "  Publishing without OTP/token (will fail if 2FA enforced - likely)" -ForegroundColor Yellow
}

# Run npm publish with stdout/stderr connected directly to the terminal (no capture).
$publishArgs = @("publish", "--access", "public") + $otpArg
Write-Host ""
Write-Host "  Running: npm $($publishArgs -join ' ')" -ForegroundColor White
Write-Host ""
& npm @publishArgs
$publishExit = $LASTEXITCODE

if ($publishExit -ne 0) {
    Write-Host ""
    Write-Host "  npm publish exited with code $publishExit" -ForegroundColor Red
    $diag = Show-NpmLogTail
    if ($diag -eq "EOTP" -or $diag -eq "E403") {
        Write-Host ""
        Write-Host "  OTP codes expire every 30 seconds - the one you entered may have expired" -ForegroundColor Yellow
        Write-Host "  during the script run. Get a FRESH 6-digit code from your authenticator." -ForegroundColor Yellow
        Write-Host "  Get a FRESH 6-digit OTP from your authenticator, OR paste a granular-access" -ForegroundColor Yellow
        Write-Host "  token (npm_xxx...) for a permanent fix:" -ForegroundColor Yellow
        $secret2 = Read-Host "  > Fresh OTP or npm_ token (Enter to abort)"
        if (-not $secret2) { Stop_ "Aborted - re-run .\ship.ps1 when ready" }
        if ($secret2 -match '^npm_[A-Za-z0-9]{30,}$') {
            & npm config set "//registry.npmjs.org/:_authToken" $secret2
            Write-Host "  Retrying with token..." -ForegroundColor Cyan
            & npm publish --access public
        } elseif ($secret2 -match '^\d{6,8}$') {
            Write-Host "  Retrying with fresh OTP..." -ForegroundColor Cyan
            & npm publish --access public --otp=$secret2
        } else {
            Stop_ "Input must be a 6-digit OTP or npm_ token. Got: '$secret2'"
        }
        $publishExit = $LASTEXITCODE
        if ($publishExit -ne 0) {
            Show-NpmLogTail | Out-Null
            Stop_ "Publish failed again - check diagnosis above"
        }
    } elseif ($diag -eq "ECONFLICT") {
        Stop_ "Version $($pkg.version) already on npm. Bump: npm version patch ; then re-run ship.ps1"
    } elseif ($diag -eq "EAUTH") {
        Stop_ "Auth lost. Run: npm login ; then re-run ship.ps1"
    } else {
        Stop_ "Publish failed - see log diagnosis above"
    }
}
CheckOK "Published $PKG_NAME@$($pkg.version) to npm"

# ============================================================
# PHASE 8: SMOKE TEST
# ============================================================
Phase 8 "Smoke test the published version"

$smokeDir = Join-Path $env:TEMP "aih-smoke-$([guid]::NewGuid().ToString().Substring(0,8))"
New-Item -ItemType Directory -Path $smokeDir | Out-Null
Push-Location $smokeDir
try {
    CheckInfo "Smoke dir: $smokeDir"
    CheckInfo "Sleeping 8s for registry propagation..."
    Start-Sleep -Seconds 8

    # Retry up to 4 times with backoff while registry propagates
    $verOut = $null
    $attempts = 0
    while ($attempts -lt 4) {
        $attempts++
        $verOut = (& npx -y "$PKG_NAME@latest" --version 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $verOut -match [regex]::Escape($TARGET_VERSION)) { break }
        if ($attempts -lt 4) {
            CheckInfo "Attempt $attempts/4: registry not propagated yet (got: $verOut). Waiting 15s..."
            Start-Sleep -Seconds 15
        }
    }
    if ($verOut -notmatch [regex]::Escape($TARGET_VERSION)) {
        Write-Host "   Last attempt output: $verOut" -ForegroundColor Yellow
        Show-NpmLogTail | Out-Null
        Stop_ "Smoke test could not fetch $TARGET_VERSION after 4 attempts. Try manually in a minute: npx -y $PKG_NAME@latest --version"
    }
    CheckOK "--version reports $verOut (after $attempts attempt(s))"

    & npx -y "$PKG_NAME@latest" init | Out-Null
    if (-not (Test-Path .\healthcheck.config.yaml)) { Stop_ "init didn't write config" }
    CheckOK "init wrote healthcheck.config.yaml"

    & npx -y "$PKG_NAME@latest" run --ai-json 2>&1 | Out-Null
    if (-not (Test-Path .\ai-healthcheck.ai.json)) { Stop_ "run didn't write ai-json" }
    $aiJson = Get-Content .\ai-healthcheck.ai.json -Raw | ConvertFrom-Json
    if (-not $aiJson.instructions_for_ai) { Stop_ "ai.json missing instructions_for_ai" }
    if (-not $aiJson.questions_to_investigate) { Stop_ "ai.json missing questions_to_investigate" }
    if (-not $aiJson.schema_notes) { Stop_ "ai.json missing schema_notes" }
    CheckOK "ai.json has instructions_for_ai + questions_to_investigate + schema_notes"
} finally {
    Pop-Location
    Remove-Item -Recurse -Force $smokeDir -ErrorAction SilentlyContinue
}

# ============================================================
# PHASE 9: GIT
# ============================================================
Phase 9 "Git: commit, tag, push"

if (-not $script:HAS_GIT) {
    CheckWarn "git missing - skipped"
} else {
    Set-Location $REPO_ROOT
    $isRepo = (& git rev-parse --is-inside-work-tree 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $isRepo -ne 'true') {
        CheckWarn "Not a git repo. To init:"
        CheckInfo "  git init"
        CheckInfo "  git remote add origin https://github.com/$($script:GH_USER)/$PKG_NAME.git"
    } else {
        $status = (& git status --porcelain 2>&1 | Out-String).Trim()
        if ($status) {
            & git add -A | Out-Null
            & git commit -m "v${TARGET_VERSION}: ship initial release" | Out-Null
            if ($LASTEXITCODE -eq 0) { CheckOK "Committed" }
            else { CheckWarn "git commit returned non-zero" }
        } else {
            CheckOK "No uncommitted changes"
        }
        $existingTag = (& git tag --list "v$TARGET_VERSION" 2>&1 | Out-String).Trim()
        if (-not $existingTag) {
            & git tag "v$TARGET_VERSION" | Out-Null
            if ($LASTEXITCODE -eq 0) { CheckOK "Tagged v$TARGET_VERSION" }
        } else {
            CheckOK "Tag v$TARGET_VERSION already exists"
        }
        $remote = (& git remote 2>&1 | Out-String).Trim()
        if ($remote) {
            if (YesNo "Push to remote ($remote)?" 'y') {
                & git push 2>&1 | Write-Host
                & git push --tags 2>&1 | Write-Host
                CheckOK "Pushed"
            }
        } else {
            CheckWarn "No git remote configured. To add:"
            CheckInfo "  git remote add origin https://github.com/$($script:GH_USER)/$PKG_NAME.git"
            CheckInfo "  git push -u origin main"
            CheckInfo "  git push --tags"
        }
    }
}

# ============================================================
# DONE
# ============================================================
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host " SHIPPED." -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host " npm:    https://www.npmjs.com/package/$PKG_NAME"
Write-Host " GitHub: https://github.com/$($script:GH_USER)/$PKG_NAME"
Write-Host ""
Write-Host " Next:"
Write-Host "   1. Positioning A/B test (DM 3 friends) -- see launch playbook chat history"
Write-Host "   2. Record 30-second screencap"
Write-Host "   3. Submit HN (URL: GitHub repo, NOT npm)"
Write-Host ""
