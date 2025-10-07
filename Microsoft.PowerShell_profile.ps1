# ============= Prompt, modules, and preferences =============
oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\kushal.omp.json" | Invoke-Expression
Import-Module Terminal-Icons

# PSReadLine
Set-PSReadLineOption -EditMode Emacs
Set-PSReadLineOption -BellStyle None
Set-PSReadLineKeyHandler -Chord 'Ctrl+d' -Function DeleteChar
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView

# Fzf
Import-Module PSFzf
Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+f' -PSReadlineChordReverseHistory 'Ctrl+r'

# Common alias
Set-Alias -Name vim -Value nvim

# Chocolatey tab-completion
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path($ChocolateyProfile)) {
  Import-Module "$ChocolateyProfile"
}

# =====================================================================
# =================== PowerShell App Launcher ==========================
# Features: open, register-app, remove-app, update-app, list-apps
# =====================================================================

# -- Global seed dictionary (will be overwritten by the auto-generated block below) --
if (-not (Get-Variable apps -Scope Global -ErrorAction SilentlyContinue)) {
    $global:apps = @{
        "chrome"  = "C:\Program Files\Google\Chrome\Application\chrome.exe"
        "vscode"  = "C:\Users\Azril\AppData\Local\Programs\Microsoft VS Code\Code.exe"
        "spotify" = "C:\Users\Azril\AppData\Roaming\Spotify\Spotify.exe"
        "notepad" = "notepad"
        "calc"    = "calc"
    }
}

# ---------------- PATCH: support URI schemes (ms-stickynotes:, ms-settings:, etc.) ----------------
function Test-UriScheme {
    param([string]$text)
    if ([string]::IsNullOrWhiteSpace($text)) { return $false, $null, $false }

    # Detect URI pattern: scheme:...
    if ($text -match '^[a-z][a-z0-9+\.\-]*:') {
        $scheme = $text.Split(':')[0]
        try {
            $exists = Test-Path -LiteralPath ("HKCR:\{0}" -f $scheme)
            return $true, $scheme, $exists
        } catch {
            return $true, $scheme, $false
        }
    }
    return $false, $null, $false
}
# -----------------------------------------------------------------------------------------------

# -- Helper: write the $apps block to $PROFILE (idempotent & multiline-safe) --
function Save-AppsToProfile {
    # Build $apps block
    $appsBlock = @()
    $appsBlock += '# ===== Auto-generated apps dictionary ====='
    $appsBlock += '$global:apps = @{'
    foreach ($k in ($apps.Keys | Sort-Object)) {
        $appsBlock += "    `"$k`" = `"$($apps[$k])`""
    }
    $appsBlock += '}'
    $appsBlock += ''  # empty line

    # Read current profile (raw to preserve newlines)
    $profilePath = $PROFILE
    $content = if (Test-Path $profilePath) { Get-Content $profilePath -Raw } else { "" }

    # Remove old block (if present), single-line regex (?s) so .* spans newlines
    $newContent = $content -replace "(?s)# ===== Auto-generated apps dictionary =====.*?}\r?\n", ""

    # Append new block at the end
    $newContent = $newContent.Trim()
    if ($newContent.Length -gt 0) { $newContent += "`r`n" }
    $newContent += ($appsBlock -join "`r`n")

    # Save back
    $newContent | Set-Content $profilePath -Encoding UTF8
}

# ---- Helpers for path/command validation ----
function Is-LikelyFilePath {
    param([string]$text)
    # If it's a URI, do not treat as file path
    $isUri, $scheme, $reg = Test-UriScheme $text
    if ($isUri) { return $false }

    # Consider it a path if it has a drive/sep or ends with .exe/.bat/.cmd
    return ($text -match '[:\\/]' -or $text -match '\.(exe|bat|cmd)$')
}

function Resolve-AppPath {
    param([string]$text)
    try {
        $isUri, $scheme, $reg = Test-UriScheme $text
        if ($isUri) {
            # URIs do not require expansion/resolution
            return $text
        }

        if (Is-LikelyFilePath $text) {
            $expanded = [Environment]::ExpandEnvironmentVariables($text)
            $resolved = Resolve-Path -LiteralPath $expanded -ErrorAction SilentlyContinue
            if ($resolved) { return $resolved.Path }
            return $expanded
        } else {
            # simple commands like 'calc', 'notepad', etc.
            return $text
        }
    } catch {
        return $text
    }
}

function Test-AppTarget {
    param([string]$target)

    $isUri, $scheme, $reg = Test-UriScheme $target
    if ($isUri) {
        if (-not $reg) {
            Write-Verbose "URI scheme '$scheme' is not present in HKCR. Ensure the supporting app is installed."
        }
        return $true
    }

    if (Is-LikelyFilePath $target) {
        $expanded = [Environment]::ExpandEnvironmentVariables($target)
        return (Test-Path -LiteralPath $expanded)
    } else {
        return [bool](Get-Command -Name $target -ErrorAction SilentlyContinue)
    }
}

# ---------------- Colored ASCII Help Screen ----------------
function Show-LauncherHelp {
    # Detect ANSI support (PowerShell 7+)
    $hasAnsi = $PSStyle -ne $null

  $banner = @'
  _    _ ______ _      _____  
 | |  | |  ____| |    |  __ \ 
 | |__| | |__  | |    | |__) |
 |  __  |  __| | |    |  _  / 
 | |  | | |____| |____| |  
 |_|  |_|______|______|_|  
                              
'@


    $lines = @(
        @{ text = "PowerShell App Launcher – Command Summary"; style = "title" }
        @{ text = "-------------------------------------------"; style = "dim"   }
        @{ text = "open <name>                  → Launch an app"; style = "cmd"   }
        @{ text = "register-app <n> <p>         → Register a new app"; style = "cmd" }
        @{ text = "  -Force, -DryRun            → Optional validation flags"; style = "dim" }
        @{ text = "update-app <n> <p>           → Update an app path/command"; style = "cmd" }
        @{ text = "  -Force, -DryRun            → Optional validation flags"; style = "dim" }
        @{ text = "remove-app <name>            → Remove app from registry"; style = "cmd" }
        @{ text = "list-apps [filter]           → Show registered apps"; style = "cmd" }
        @{ text = "";                              style = "" }
        @{ text = "Quick aliases:";                style = "title2" }
        @{ text = "  o, regapp, updapp, rmapp, apps / la"; style = "cmd" }
        @{ text = "";                              style = "" }
        @{ text = "Examples:";                     style = "title2" }
        @{ text = "  open vscode";                 style = "ex" }
        @{ text = "  regapp store ms-windows-store:"; style = "ex" }
        @{ text = "  updapp vscode 'C:\New\Path\Code.exe'"; style = "ex" }
        @{ text = "  rmapp store";                 style = "ex" }
        @{ text = "  apps ms";                     style = "ex" }
    )

    if ($hasAnsi) {
        # ANSI styles (PowerShell 7+)
        $c = [pscustomobject]@{
            accent  = $PSStyle.Foreground.Cyan + $PSStyle.Bold
            title   = $PSStyle.Foreground.BrightYellow + $PSStyle.Bold
            title2  = $PSStyle.Foreground.BrightYellow
            cmd     = $PSStyle.Foreground.BrightGreen
            ex      = $PSStyle.Foreground.BrightBlue
            dim     = $PSStyle.Foreground.BrightBlack
            reset   = $PSStyle.Reset
        }

        # Banner
        Write-Host ($c.accent + $banner + $c.reset)

        foreach ($ln in $lines) {
            $style =
                if ($ln.style -eq "title")  { $c.title }
                elseif ($ln.style -eq "title2") { $c.title2 }
                elseif ($ln.style -eq "cmd") { $c.cmd }
                elseif ($ln.style -eq "ex")  { $c.ex }
                elseif ($ln.style -eq "dim") { $c.dim }
                else { "" }
            Write-Host ($style + $ln.text + $c.reset)
        }
    }
    else {
        # Fallback for Windows PowerShell 5.1 (no $PSStyle)
        Write-Host $banner -ForegroundColor Cyan
        Write-Host "PowerShell App Launcher – Command Summary" -ForegroundColor Yellow
        Write-Host "-------------------------------------------" -ForegroundColor DarkGray
        Write-Host "open <name>                  → Launch an app" -ForegroundColor Green
        Write-Host "register-app <n> <p>         → Register a new app" -ForegroundColor Green
        Write-Host "  -Force, -DryRun            → Optional validation flags" -ForegroundColor DarkGray
        Write-Host "update-app <n> <p>           → Update an app path/command" -ForegroundColor Green
        Write-Host "  -Force, -DryRun            → Optional validation flags" -ForegroundColor DarkGray
        Write-Host "remove-app <name>            → Remove app from registry" -ForegroundColor Green
        Write-Host "list-apps [filter]           → Show registered apps" -ForegroundColor Green
        Write-Host ""
        Write-Host "Quick aliases:" -ForegroundColor Yellow
        Write-Host "  o, regapp, updapp, rmapp, apps / la" -ForegroundColor Green
        Write-Host ""
        Write-Host "Examples:" -ForegroundColor Yellow
        Write-Host "  open vscode" -ForegroundColor Blue
        Write-Host "  regapp store ms-windows-store:" -ForegroundColor Blue
        Write-Host "  updapp vscode 'C:\New\Path\Code.exe'" -ForegroundColor Blue
        Write-Host "  rmapp store" -ForegroundColor Blue
        Write-Host "  apps ms" -ForegroundColor Blue
    }
}

# -- Launcher: open (with integrated help) --
function open {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$app
    )

    $key = $app.ToLower()

    # ===== HELP MODE =====
    if ($key -in @('--help','-h','/h','help','/?')) {
        Show-LauncherHelp
        return
    }

    if ($apps.ContainsKey($key)) {
        $target = Resolve-AppPath $apps[$key]
        if (-not (Test-AppTarget $target)) {
            Write-Warning "Target for '$key' not found/command unavailable: $target"
            Write-Output  "ℹ️  Update with: update-app `"$key`" `"<new-path-or-command>`""
            return
        }
        Write-Output "🚀 Launching $key ..."
        try { Start-Process $target } catch { Write-Error "Failed to start: $target" }
    } else {
        Write-Output "❌ App '$app' is not registered with 'open'."
        Write-Output "ℹ️  See: list-apps   |   quick add: register-app <name> <path>"
        Write-Output "ℹ️  Help: open --help"
    }
}

# -- Register a new app (validation + -Force + -DryRun) --
function register-app {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$name,
        [Parameter(Mandatory=$true, Position=1)]
        [string]$path,
        [switch]$Force,
        [switch]$DryRun
    )

    $lowerName = $name.ToLower()
    $resolved  = Resolve-AppPath $path
    $exists    = Test-AppTarget $resolved
    $already   = $apps.ContainsKey($lowerName)

    if (-not $exists -and -not $Force) {
        Write-Warning "Target not found/command unavailable: $path"
        Write-Output  "ℹ️  If you are sure, run again with -Force:"
        Write-Output  "    register-app `"$name`" `"$path`" -Force"
        return
    }

    if ($DryRun) {
        if ($already) {
            Write-Output "🔎 DRY-RUN: register-app"
            Write-Output "    Name  : $lowerName"
            Write-Output "    Old   : $($apps[$lowerName])"
            Write-Output "    New   : $path"
            Write-Output "    File  : $PROFILE (unchanged)"
        } else {
            Write-Output "🔎 DRY-RUN: register-app"
            Write-Output "    Name  : $lowerName"
            Write-Output "    New   : $path"
            Write-Output "    File  : $PROFILE (unchanged)"
        }
        if (-not $exists) {
            Write-Output "⚠️  Note: target not verified to exist (use -Force to bypass validation when not dry-run)."
        }
        return
    }

    # Persist change (not dry-run)
    $apps[$lowerName] = $path  # keep the user's input as-is
    Save-AppsToProfile

    if ($exists) {
        Write-Output "✅ Registered '$lowerName' → $path"
    } else {
        Write-Output "✅ Registered (forced) '$lowerName' → $path"
        Write-Output "⚠️  Note: target not verified to exist. Ensure the path/command is correct."
    }
    Write-Output "ℹ️  Use 'list-apps' to verify."
}

# -- Remove an app --
function remove-app {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$name
    )
    $lowerName = $name.ToLower()
    if ($apps.ContainsKey($lowerName)) {
        $apps.Remove($lowerName)
        Save-AppsToProfile
        Write-Output "🗑️  App '$lowerName' removed."
        Write-Output "ℹ️  Use 'list-apps' to verify."
    } else {
        Write-Output "⚠️  App '$name' is not in the registry."
    }
}

# -- Update app path/command (validation + -Force + -DryRun) --
function update-app {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$name,
        [Parameter(Mandatory=$true, Position=1)]
        [string]$newPath,
        [switch]$Force,
        [switch]$DryRun
    )

    $lowerName = $name.ToLower()
    if (-not $apps.ContainsKey($lowerName)) {
        Write-Output "⚠️  App '$name' is not registered. Use:"
        Write-Output "    register-app `"$name`" `"$newPath`""
        return
    }

    $resolved = Resolve-AppPath $newPath
    $exists   = Test-AppTarget $resolved
    $oldPath  = $apps[$lowerName]

    if (-not $exists -and -not $Force) {
        Write-Warning "New target not found/command unavailable: $newPath"
        Write-Output  "ℹ️  If you are sure, run again with -Force:"
        Write-Output  "    update-app `"$name`" `"$newPath`" -Force"
        return
    }

    if ($DryRun) {
        Write-Output "🔎 DRY-RUN: update-app"
        Write-Output "    Name  : $lowerName"
        Write-Output "    Old   : $oldPath"
        Write-Output "    New   : $newPath"
        Write-Output "    File  : $PROFILE (unchanged)"
        if (-not $exists) {
            Write-Output "⚠️  Note: new target not verified to exist (use -Force to bypass validation when not dry-run)."
        }
        return
    }

    # Persist change (not dry-run)
    $apps[$lowerName] = $newPath
    Save-AppsToProfile

    Write-Output "🔁 Updated '$lowerName'"
    Write-Output "    Old → $oldPath"
    Write-Output "    New → $newPath"
    if (-not $exists) {
        Write-Output "⚠️  Note: new target not verified to exist (forced)."
    }
}

# -- List apps --
function list-apps {
    param([string]$filter)

    $pairs = if ([string]::IsNullOrWhiteSpace($filter)) {
        $apps.GetEnumerator() | Sort-Object Key
    } else {
        $apps.GetEnumerator() | Where-Object { $_.Key -like "*$filter*" } | Sort-Object Key
    }

    if (-not $pairs) {
        if ($filter) {
            Write-Output "⚠️  No apps match the filter: '$filter'."
        } else {
            Write-Output "⚠️  No apps registered yet."
        }
        return
    }

    $maxKey = ($pairs | ForEach-Object { $_.Key.Length } | Measure-Object -Maximum).Maximum
    $headerKey = "Name".PadRight([Math]::Max($maxKey, 4))
    Write-Output "📋 Registered apps:"
    Write-Output "$headerKey | Path"
    Write-Output ("-" * $headerKey.Length + "-+-" + "-" * 40)
    foreach ($p in $pairs) {
        $name = $p.Key.PadRight($maxKey)
        Write-Output "$name | $($p.Value)"
    }
}

# -- Startup Message --
# Write-Output "✅ Please register these applications in your PowerShell profile:"
# $apps.Keys | Sort-Object | ForEach-Object { Write-Output "   - $_" }
Write-Output "ℹ️  Main Command: open <name>, register-app, update-app, remove-app, list-apps"
Write-Output "ℹ️  Complete Help: open --help"

# ================= Aliases =================

# Short aliases
Set-Alias o        open
Set-Alias regapp   register-app
Set-Alias updapp   update-app
Set-Alias rmapp    remove-app

# 'apps' wrapper that forwards filter automatically
function apps {
    param([string]$filter)
    if ($PSBoundParameters.ContainsKey('filter') -and $null -ne $filter -and $filter.Trim().Length -gt 0) {
        list-apps $filter
    } elseif ($args.Count -gt 0) {
        list-apps $args[0]
    } else {
        list-apps
    }
}
Set-Alias la apps

# =====================================================================
# ===== Auto-generated apps dictionary =====
# (This section is maintained automatically by Save-AppsToProfile)
$global:apps = @{
    "arduino"   = "C:\Program Files\Arduino IDE\Arduino IDE.exe"
    "calc"      = "calc"
    "chrome"    = "C:\Program Files\Google\Chrome\Application\chrome.exe"
    "discord"   = "C:\Users\azril\AppData\Local\Discord\app-1.0.9209\Discord.exe"
    "explorer"  = "C:\Windows\explorer.exe"
    "godot"     = "C:\Program Files\Godot_v4.4.1\Godot_v4.4.1-stable_mono_win64.exe"
    "msedge"    = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    "msexcel"   = "C:\Program Files\Microsoft Office\root\Office16\EXCEL.exe"
    "mspoint"   = "C:\Program Files\Microsoft Office\root\Office16\POWERPNT.exe"
    "msword"    = "C:\Program Files\Microsoft Office\root\Office16\WINWORD.exe"
    "notepad"   = "notepad"
    "notepad++" = "C:\Program Files\Notepad++\notepad++.exe"
    "paint"     = "mspaint"
    "pcsx2"     = "C:\Users\azril\Documents\pcsx2-v2.3.88-windows-x64-Qt\pcsx2-qt.exe"
    "postman"   = "C:\Users\azril\AppData\Local\Postman\Postman.exe"
    "spotify"   = "C:\Users\Azril\AppData\Roaming\Spotify\Spotify.exe"
    "steam"     = "C:\Program Files (x86)\Steam\steam.exe"
    "vbox"      = "C:\Program Files\Oracle\VirtualBox\VirtualBox.exe"
    "vlc"       = "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
    "vscode"    = "C:\Users\Azril\AppData\Local\Programs\Microsoft VS Code\Code.exe"
}
# =====================================================================


# =============================== ADD-ON OVERRIDES ===============================
# 1) Override HELP banner to short "HELP" ASCII (colors & texts below remain unchanged)
function Show-LauncherHelp {
    $hasAnsi = $PSStyle -ne $null
    $banner = @'
  _    _ ______ _      _____  
 | |  | |  ____| |    |  __ \ 
 | |__| | |__  | |    | |__) |
 |  __  |  __| | |    |  _  / 
 | |  | | |____| |____| |  
 |_|  |_|______|______|_| 
                              
'@
    $lines = @(
        @{ text = "PowerShell App Launcher – Command Summary"; style = "title" }
        @{ text = "-------------------------------------------"; style = "dim"   }
        @{ text = "open <name>                  → Launch an app"; style = "cmd"   }
        @{ text = "register-app <n> <p>         → Register a new app"; style = "cmd" }
        @{ text = "  -Force, -DryRun            → Optional validation flags"; style = "dim" }
        @{ text = "update-app <n> <p>           → Update an app path/command"; style = "cmd" }
        @{ text = "  -Force, -DryRun            → Optional validation flags"; style = "dim" }
        @{ text = "remove-app <name>            → Remove app from registry"; style = "cmd" }
        @{ text = "list-apps [filter]           → Show registered apps"; style = "cmd" }
        @{ text = "";                              style = "" }
        @{ text = "Quick aliases:";                style = "title2" }
        @{ text = "  o, regapp, updapp, rmapp, apps / la"; style = "cmd" }
        @{ text = "";                              style = "" }
        @{ text = "Examples:";                     style = "title2" }
        @{ text = "  open vscode";                 style = "ex" }
        @{ text = "  regapp store ms-windows-store:"; style = "ex" }
        @{ text = "  updapp vscode 'C:\New\Path\Code.exe'"; style = "ex" }
        @{ text = "  rmapp store";                 style = "ex" }
        @{ text = "  apps ms";                     style = "ex" }
    )

    if ($hasAnsi) {
        $c = [pscustomobject]@{
            accent  = $PSStyle.Foreground.Cyan + $PSStyle.Bold
            title   = $PSStyle.Foreground.BrightYellow + $PSStyle.Bold
            title2  = $PSStyle.Foreground.BrightYellow
            cmd     = $PSStyle.Foreground.BrightGreen
            ex      = $PSStyle.Foreground.BrightBlue
            dim     = $PSStyle.Foreground.BrightBlack
            reset   = $PSStyle.Reset
        }
        Write-Host ($c.accent + $banner + $c.reset)
        foreach ($ln in $lines) {
            $style =
                if ($ln.style -eq "title")      { $c.title }
                elseif ($ln.style -eq "title2") { $c.title2 }
                elseif ($ln.style -eq "cmd")    { $c.cmd }
                elseif ($ln.style -eq "ex")     { $c.ex }
                elseif ($ln.style -eq "dim")    { $c.dim }
                else { "" }
            Write-Host ($style + $ln.text + $c.reset)
        }
    } else {
        Write-Host $banner -ForegroundColor Cyan
        Write-Host "PowerShell App Launcher – Command Summary" -ForegroundColor Yellow
        Write-Host "-------------------------------------------" -ForegroundColor DarkGray
        Write-Host "open <name>                  → Launch an app" -ForegroundColor Green
        Write-Host "register-app <n> <p>         → Register a new app" -ForegroundColor Green
        Write-Host "  -Force, -DryRun            → Optional validation flags" -ForegroundColor DarkGray
        Write-Host "update-app <n> <p>           → Update an app path/command" -ForegroundColor Green
        Write-Host "  -Force, -DryRun            → Optional validation flags" -ForegroundColor DarkGray
        Write-Host "remove-app <name>            → Remove app from registry" -ForegroundColor Green
        Write-Host "list-apps [filter]           → Show registered apps" -ForegroundColor Green
        Write-Host ""
        Write-Host "Quick aliases:" -ForegroundColor Yellow
        Write-Host "  o, regapp, updapp, rmapp, apps / la" -ForegroundColor Green
        Write-Host ""
        Write-Host "Examples:" -ForegroundColor Yellow
        Write-Host "  open vscode" -ForegroundColor Blue
        Write-Host "  regapp store ms-windows-store:" -ForegroundColor Blue
        Write-Host "  updapp vscode 'C:\New\Path\Code.exe'" -ForegroundColor Blue
        Write-Host "  rmapp store" -ForegroundColor Blue
        Write-Host "  apps ms" -ForegroundColor Blue
    }
}

# 2) Add banner + color table for list-apps
function Show-AppsBanner {
    $hasAnsi = $PSStyle -ne $null
    $banner = @'
    _    ____  ____  _____ 
   / \  |  _ \|  _ \| ____|
  / _ \ | |_) | |_) |  _|  
 / ___ \|  __/|  __/| |___ 
/_/   \_\_|   |_|   |_____|
'@
    if ($hasAnsi) {
        $c = [pscustomobject]@{
            accent = $PSStyle.Foreground.Cyan + $PSStyle.Bold
            reset  = $PSStyle.Reset
        }
        Write-Host ($c.accent + $banner + $c.reset)
    } else {
        Write-Host $banner -ForegroundColor Cyan
    }
}

function list-apps {
    param([string]$filter)

    $pairs = if ([string]::IsNullOrWhiteSpace($filter)) {
        $apps.GetEnumerator() | Sort-Object Key
    } else {
        $apps.GetEnumerator() | Where-Object { $_.Key -like "*$filter*" } | Sort-Object Key
    }

    Show-AppsBanner

    if (-not $pairs) {
        if ($filter) {
            Write-Host "No apps match filter: '$filter'." -ForegroundColor Yellow
        } else {
            Write-Host "No apps registered yet." -ForegroundColor Yellow
        }
        return
    }

    $nameWidth = [Math]::Max(4, ($pairs | ForEach-Object { $_.Key.Length } | Measure-Object -Maximum).Maximum)
    $pathWidth = [Math]::Max(4, ($pairs | ForEach-Object { $_.Value.Length } | Measure-Object -Maximum).Maximum)
    $totalWidth = $nameWidth + $pathWidth + 5   # borders + separator

    $hasAnsi = $PSStyle -ne $null
    if ($hasAnsi) {
        $c = [pscustomobject]@{
            box    = $PSStyle.Foreground.BrightBlack
            title  = $PSStyle.Foreground.BrightYellow + $PSStyle.Bold
            name   = $PSStyle.Foreground.BrightGreen
            path   = $PSStyle.Foreground.BrightBlue
            dim    = $PSStyle.Foreground.BrightBlack
            cnt    = $PSStyle.Foreground.Cyan
            reset  = $PSStyle.Reset
        }

        $top    = $c.box + "+" + ("-" * ($totalWidth-2)) + "+" + $c.reset
        $hdrTxt = (" Name".PadRight($nameWidth) + " | " + "Path".PadRight($pathWidth))
        $hdr    = $c.box + "|" + $c.title + $hdrTxt + $c.reset + $c.box + "|" + $c.reset
        $sep    = $c.box + "+" + ("=" * ($totalWidth-2)) + "+" + $c.reset

        Write-Host $top
        Write-Host $hdr
        Write-Host $sep

        foreach ($p in $pairs) {
            $name = ($p.Key).PadRight($nameWidth)
            $path = ($p.Value).PadRight($pathWidth)
            $line = $c.box + "|" + $c.name + $name + $c.reset + $c.box + " | " + $c.reset + $c.path + $path + $c.reset + $c.box + "|" + $c.reset
            Write-Host $line
        }

        $bottom = $c.box + "+" + ("-" * ($totalWidth-2)) + "+" + $c.reset
        Write-Host $bottom
        Write-Host ($c.cnt + ("Total apps: {0}" -f ($pairs.Count)) + $c.reset)

        if ($filter) {
            Write-Host ($c.dim + ("Filter: '{0}'" -f $filter) + $c.reset)
        }
    } else {
        $top    = "+" + ("-" * ($totalWidth-2)) + "+"
        $hdrTxt = (" Name".PadRight($nameWidth) + " | " + "Path".PadRight($pathWidth))
        $sep    = "+" + ("=" * ($totalWidth-2)) + "+"

        Write-Host $top -ForegroundColor DarkGray
        Write-Host ("|" + $hdrTxt + "|") -ForegroundColor Yellow
        Write-Host $sep -ForegroundColor DarkGray

        foreach ($p in $pairs) {
            $name = ($p.Key).PadRight($nameWidth)
            $path = ($p.Value).PadRight($pathWidth)
            Write-Host ("|" + $name + " | " + $path + "|")
        }

        Write-Host ("+" + ("-" * ($totalWidth-2)) + "+") -ForegroundColor DarkGray
        Write-Host ("Total apps: {0}" -f ($pairs.Count)) -ForegroundColor Cyan
        if ($filter) { Write-Host ("Filter: '{0}'" -f $filter) -ForegroundColor DarkGray }
    }
}
# ============================= END ADD-ON OVERRIDES =============================
