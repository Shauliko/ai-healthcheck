# ship-gui.ps1 -- Windows Forms GUI wrapper for the ai-healthcheck publish flow.
#
# Usage:
#   cd C:\dev\ai-healthcheck
#   .\ship-gui.ps1
#
# Or just double-click the file in Explorer (after enabling PowerShell .ps1 exec).

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$REPO_ROOT      = "C:\dev\ai-healthcheck"
$PKG_NAME       = "ai-healthcheck"
$TARGET_VERSION = "0.1.0"

# ---------- helpers ----------
function Get-NpmUser {
    $u = (& npm whoami 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { return $null }
    return $u
}
function Test-RepoOk {
    if (-not (Test-Path "$REPO_ROOT\package.json")) { return $false, "package.json missing" }
    try {
        $pkg = Get-Content "$REPO_ROOT\package.json" -Raw | ConvertFrom-Json
        if ($pkg.name -ne $PKG_NAME) { return $false, "name mismatch: $($pkg.name)" }
        if ($pkg.version -ne $TARGET_VERSION) { return $false, "version: $($pkg.version)" }
        return $true, "v$($pkg.version)"
    } catch { return $false, "JSON invalid: $($_.Exception.Message)" }
}

# ---------- form ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = "ai-healthcheck shipper"
$form.Size = New-Object System.Drawing.Size(720, 625)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 250)

# Header
$header = New-Object System.Windows.Forms.Label
$header.Text = "ai-healthcheck shipper"
$header.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$header.AutoSize = $true
$header.Location = New-Object System.Drawing.Point(20, 15)
$form.Controls.Add($header)

$subheader = New-Object System.Windows.Forms.Label
$subheader.Text = "Publish $PKG_NAME to npm. Token path bypasses 2FA OTP prompts."
$subheader.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$subheader.ForeColor = [System.Drawing.Color]::DimGray
$subheader.AutoSize = $true
$subheader.Location = New-Object System.Drawing.Point(20, 50)
$form.Controls.Add($subheader)

# Status panel
$statusPanel = New-Object System.Windows.Forms.GroupBox
$statusPanel.Text = "Status"
$statusPanel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$statusPanel.Location = New-Object System.Drawing.Point(20, 80)
$statusPanel.Size = New-Object System.Drawing.Size(670, 90)
$form.Controls.Add($statusPanel)

$lblRepo = New-Object System.Windows.Forms.Label
$lblRepo.Text = "Repo:   checking..."
$lblRepo.Font = New-Object System.Drawing.Font("Consolas", 9)
$lblRepo.AutoSize = $true
$lblRepo.Location = New-Object System.Drawing.Point(15, 25)
$statusPanel.Controls.Add($lblRepo)

$lblNpm = New-Object System.Windows.Forms.Label
$lblNpm.Text = "npm:    checking..."
$lblNpm.Font = New-Object System.Drawing.Font("Consolas", 9)
$lblNpm.AutoSize = $true
$lblNpm.Location = New-Object System.Drawing.Point(15, 45)
$statusPanel.Controls.Add($lblNpm)

$lblPub = New-Object System.Windows.Forms.Label
$lblPub.Text = "Publish: not yet attempted"
$lblPub.Font = New-Object System.Drawing.Font("Consolas", 9)
$lblPub.AutoSize = $true
$lblPub.Location = New-Object System.Drawing.Point(15, 65)
$statusPanel.Controls.Add($lblPub)

# Token / OTP input
$lblToken = New-Object System.Windows.Forms.Label
$lblToken.Text = "npm token (npm_...) -- RECOMMENDED -- or 6-digit OTP:"
$lblToken.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblToken.AutoSize = $true
$lblToken.Location = New-Object System.Drawing.Point(20, 185)
$form.Controls.Add($lblToken)

$txtToken = New-Object System.Windows.Forms.TextBox
$txtToken.Font = New-Object System.Drawing.Font("Consolas", 10)
$txtToken.Location = New-Object System.Drawing.Point(20, 208)
$txtToken.Size = New-Object System.Drawing.Size(670, 26)
$txtToken.UseSystemPasswordChar = $true
$form.Controls.Add($txtToken)

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = "Token persists across runs. OTP must be re-entered each publish."
$lblHint.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$lblHint.ForeColor = [System.Drawing.Color]::DimGray
$lblHint.AutoSize = $true
$lblHint.Location = New-Object System.Drawing.Point(20, 238)
$form.Controls.Add($lblHint)

# Get-token button
# Row 1 of action buttons: setup helpers
$btn2FA = New-Object System.Windows.Forms.Button
$btn2FA.Text = "1. Enable npm 2FA"
$btn2FA.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btn2FA.Location = New-Object System.Drawing.Point(20, 262)
$btn2FA.Size = New-Object System.Drawing.Size(155, 32)
$btn2FA.BackColor = [System.Drawing.Color]::FromArgb(255, 152, 0)
$btn2FA.ForeColor = [System.Drawing.Color]::White
$btn2FA.FlatStyle = "Flat"
$form.Controls.Add($btn2FA)

$btnToken = New-Object System.Windows.Forms.Button
$btnToken.Text = "2. Get Token (after 2FA)"
$btnToken.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$btnToken.Location = New-Object System.Drawing.Point(180, 262)
$btnToken.Size = New-Object System.Drawing.Size(180, 32)
$btnToken.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnToken.ForeColor = [System.Drawing.Color]::White
$btnToken.FlatStyle = "Flat"
$form.Controls.Add($btnToken)

# Publish button
$btnPublish = New-Object System.Windows.Forms.Button
$btnPublish.Text = "3. PUBLISH TO NPM"
$btnPublish.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnPublish.Location = New-Object System.Drawing.Point(365, 262)
$btnPublish.Size = New-Object System.Drawing.Size(195, 32)
$btnPublish.BackColor = [System.Drawing.Color]::FromArgb(40, 167, 69)
$btnPublish.ForeColor = [System.Drawing.Color]::White
$btnPublish.FlatStyle = "Flat"
$form.Controls.Add($btnPublish)

# Row 2 of action buttons: post-publish
$btnTests = New-Object System.Windows.Forms.Button
$btnTests.Text = "Re-run Tests"
$btnTests.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$btnTests.Location = New-Object System.Drawing.Point(565, 262)
$btnTests.Size = New-Object System.Drawing.Size(125, 32)
$form.Controls.Add($btnTests)

$btnSmoke = New-Object System.Windows.Forms.Button
$btnSmoke.Text = "Smoke Test (post-publish)"
$btnSmoke.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$btnSmoke.Location = New-Object System.Drawing.Point(20, 300)
$btnSmoke.Size = New-Object System.Drawing.Size(180, 28)
$form.Controls.Add($btnSmoke)

$btnRelogin = New-Object System.Windows.Forms.Button
$btnRelogin.Text = "Re-login (passkey-friendly)"
$btnRelogin.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$btnRelogin.Location = New-Object System.Drawing.Point(205, 300)
$btnRelogin.Size = New-Object System.Drawing.Size(190, 28)
$form.Controls.Add($btnRelogin)

$btnTrustPub = New-Object System.Windows.Forms.Button
$btnTrustPub.Text = "Trusted Publishing (advanced)"
$btnTrustPub.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$btnTrustPub.Location = New-Object System.Drawing.Point(400, 300)
$btnTrustPub.Size = New-Object System.Drawing.Size(190, 28)
$form.Controls.Add($btnTrustPub)

# Log area
$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "Log:"
$lblLog.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblLog.AutoSize = $true
$lblLog.Location = New-Object System.Drawing.Point(20, 343)
$form.Controls.Add($lblLog)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$logBox.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$logBox.ForeColor = [System.Drawing.Color]::FromArgb(200, 220, 200)
$logBox.Location = New-Object System.Drawing.Point(20, 363)
$logBox.Size = New-Object System.Drawing.Size(670, 195)
$form.Controls.Add($logBox)

# ---------- behavior ----------
function Log($msg, $color = "default") {
    $ts = Get-Date -Format "HH:mm:ss"
    $logBox.AppendText("[$ts] $msg`r`n")
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Refresh-Status {
    $ok, $detail = Test-RepoOk
    $lblRepo.Text = if ($ok) { "Repo:   OK     $detail   ($REPO_ROOT)" } else { "Repo:   FAIL   $detail" }
    $lblRepo.ForeColor = if ($ok) { [System.Drawing.Color]::FromArgb(0, 120, 0) } else { [System.Drawing.Color]::Red }

    $user = Get-NpmUser
    if ($user) {
        $lblNpm.Text = "npm:    OK     logged in as $user"
        $lblNpm.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 0)
        $script:NPM_USER = $user
    } else {
        $lblNpm.Text = "npm:    FAIL   not logged in (run 'npm login' in terminal first)"
        $lblNpm.ForeColor = [System.Drawing.Color]::Red
        $script:NPM_USER = $null
    }

    # Check if package is already on npm with our version
    $existsOut = (& npm view "$PKG_NAME@$TARGET_VERSION" version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -eq 0 -and $existsOut -eq $TARGET_VERSION) {
        $lblPub.Text = "Publish: ALREADY ON NPM   $PKG_NAME@$TARGET_VERSION"
        $lblPub.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 0)
    } else {
        $lblPub.Text = "Publish: not yet on npm"
        $lblPub.ForeColor = [System.Drawing.Color]::DimGray
    }
}

$btn2FA.Add_Click({
    $user = if ($script:NPM_USER) { $script:NPM_USER } else { "YOUR_USERNAME" }
    $url = "https://www.npmjs.com/settings/$user/profile"
    Log "Opening: $url"
    Log "  -> Scroll to 'Two-Factor Authentication'"
    Log "  -> Click 'Enable 2FA' -> choose 'Authorization and Publishing'"
    Log "  -> Scan the QR code with Google Authenticator, Authy, or 1Password"
    Log "  -> Save the recovery codes somewhere safe"
    Log "  -> Come back here, get the 6-digit code from your authenticator app"
    Log "  -> Paste that code in the field above, then click PUBLISH"
    Start-Process $url
})

$btnToken.Add_Click({
    $user = if ($script:NPM_USER) { $script:NPM_USER } else { "YOUR_USERNAME" }
    $url = "https://www.npmjs.com/settings/$user/tokens/granular-access-tokens"
    Log "Opening: $url"
    Log "NOTE: 'Bypass 2FA' option requires 2FA to be enabled on your account first."
    Log "  If you cannot toggle Bypass 2FA, click 'Enable npm 2FA' first."
    Log "  Then come back here, create the token with Bypass 2FA = YES."
    Start-Process $url
})

$btnTrustPub.Add_Click({
    Log "Trusted Publishing: GitHub Actions publishes via OIDC, no token needed."
    Log "  Catch-22: requires the package to exist on npm first (publish manually once)."
    Log "  After that, configure at: https://www.npmjs.com/package/$PKG_NAME/access"
    Log "  Workflow already in repo: .github/workflows/publish.yml"
    $url = "https://docs.npmjs.com/trusted-publishers"
    Start-Process $url
})

$btnRelogin.Add_Click({
    Log "Re-authenticating with browser (works with passkey/Windows Hello 2FA)..."
    Log "  Step 1: logging out current session"
    & npm logout 2>&1 | Out-Null
    Log "  Step 2: opening browser for fresh login..."
    Log "  -- a browser window opens; complete the npm login flow there, including your passkey"
    Log "  -- when login finishes, come back here, clear the token field, click PUBLISH"
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "npm login --auth-type=web"
    Log "  (a NEW PowerShell window opened for the login - keep this GUI open)"
})

$btnTests.Add_Click({
    $btnTests.Enabled = $false
    Log "Running tests..."
    Push-Location $REPO_ROOT
    try {
        $out = (& node --test --test-reporter=tap "test/*.test.js" 2>&1 | Out-String)
        if ($out -match "(?m)^[^a-zA-Z]*pass\s+11\b") {
            Log "Tests: 11/11 PASS"
        } else {
            Log "Tests: FAIL  see terminal that launched ship-gui.ps1 for full output"
            Write-Host $out
        }
    } finally {
        Pop-Location
        $btnTests.Enabled = $true
    }
})

$btnPublish.Add_Click({
    if (-not $script:NPM_USER) {
        Log "ERROR: not logged in to npm. Open a terminal and run: npm login"
        return
    }
    $secret = $txtToken.Text.Trim()
    # Note: empty $secret is VALID - it triggers --auth-type=web (passkey/browser flow)
    $btnPublish.Enabled = $false
    Push-Location $REPO_ROOT
    try {
        if ($secret -match "^npm_[A-Za-z0-9_-]{30,}$") {
            Log "Token detected. Registering with npm config..."
            & npm config set "//registry.npmjs.org/:_authToken" $secret | Out-Null
            Log "Publishing $PKG_NAME@$TARGET_VERSION ..."
            $out = (& npm publish --access public 2>&1 | Out-String)
        } elseif ($secret -match "^\d{6,8}$") {
            Log "OTP detected. Publishing with --otp ..."
            $out = (& npm publish --access public --otp=$secret 2>&1 | Out-String)
        } elseif (-not $secret -or $secret -eq "") {
            Log "No OTP/token provided. Using browser auth (works with passkey/Windows Hello 2FA)..."
            Log "A browser window will open for you to confirm the publish."
            $out = (& npm publish --access public --auth-type=web 2>&1 | Out-String)
        } else {
            Log "ERROR: input must be an npm_ token, 6-8 digit OTP, or empty (for browser auth)"
            return
        }

        # Print npm output to log
        foreach ($line in ($out -split "`r?`n")) {
            if ($line.Trim()) { Log "  npm> $line" }
        }

        if ($LASTEXITCODE -eq 0 -and $out -match "\+ $PKG_NAME@") {
            Log ""
            Log "SUCCESS: $PKG_NAME@$TARGET_VERSION published to npm"
            Log "Verify: https://www.npmjs.com/package/$PKG_NAME"
            $txtToken.Text = ""
            Refresh-Status
        } else {
            Log ""
            Log "PUBLISH FAILED (exit $LASTEXITCODE)"
            if ($out -match "Two-factor|bypass 2fa") {
                Log "  -> Token doesn't have 'Bypass 2FA' enabled, or OTP expired."
                Log "  -> Get a fresh token: click 'Get a Bypass-2FA Token' button"
            } elseif ($out -match "EPUBLISHCONFLICT|already published") {
                Log "  -> Version already on npm. Bump version: npm version patch"
            } elseif ($out -match "E401|ENEEDAUTH") {
                Log "  -> Token invalid. Get a new one."
            }
        }
    } finally {
        Pop-Location
        $btnPublish.Enabled = $true
    }
})

$btnSmoke.Add_Click({
    $btnSmoke.Enabled = $false
    $smokeDir = Join-Path $env:TEMP ("aih-gui-smoke-" + [guid]::NewGuid().ToString().Substring(0,8))
    New-Item -ItemType Directory -Path $smokeDir | Out-Null
    Push-Location $smokeDir
    try {
        Log "Smoke test in: $smokeDir"
        Log "  -> npx -y $PKG_NAME@latest --version"
        $v = (& npx -y "$PKG_NAME@latest" --version 2>&1 | Out-String).Trim()
        Log "     => $v"
        if ($LASTEXITCODE -eq 0 -and $v -match [regex]::Escape($TARGET_VERSION)) {
            Log "Smoke test: PASS"
        } else {
            Log "Smoke test: FAIL  (registry may need more propagation time - try in 60s)"
        }
    } finally {
        Pop-Location
        Remove-Item -Recurse -Force $smokeDir -ErrorAction SilentlyContinue
        $btnSmoke.Enabled = $true
    }
})

# Initial refresh
$form.Add_Shown({
    Log "ai-healthcheck shipper GUI ready"
    Log "Repo: $REPO_ROOT"
    Refresh-Status
    if (-not $script:NPM_USER) {
        Log ""
        Log "NOT LOGGED IN to npm. Open PowerShell and run:  npm login"
        Log "Then close this window and re-launch ship-gui.ps1"
    } else {
        Log "Ready. CHOOSE ONE PATH:"
        Log "  A) Click '1. Enable npm 2FA' -> set up authenticator -> paste OTP -> PUBLISH"
        Log "  B) Click '2. Get Token' -> create with Bypass 2FA -> paste npm_ -> PUBLISH"
        Log "     (Path B requires 2FA already on - npm catch-22)"
        Log ""
        Log "Most users: do Path A. It is 60 seconds and never breaks."
        Log ""
        Log "PASSKEY/WINDOWS HELLO 2FA: leave token field BLANK, click PUBLISH."
        Log "  GUI will use --auth-type=web which opens a browser for passkey confirm."
        Log "  If that fails with 'may not perform that action', click 'Re-login' first."
    }
})

[void]$form.ShowDialog()
