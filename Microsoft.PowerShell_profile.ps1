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

# -- Global seed dictionary (akan di-overwrite oleh blok auto-generated di bawah) --
if (-not (Get-Variable apps -Scope Global -ErrorAction SilentlyContinue)) {
    $global:apps = @{
        "chrome"  = "C:\Program Files\Google\Chrome\Application\chrome.exe"
        "vscode"  = "C:\Users\Azril\AppData\Local\Programs\Microsoft VS Code\Code.exe"
        "spotify" = "C:\Users\Azril\AppData\Roaming\Spotify\Spotify.exe"
        "notepad" = "notepad"
        "calc"    = "calc"
    }
}

# --- FIXED: Deteksi URI yang mengabaikan path Windows (drive & UNC) ---
function Test-UriScheme {
    param([string]$text)
    if ([string]::IsNullOrWhiteSpace($text)) { return $false, $null, $false }

    $t = $text.Trim()

    # EXCLUDE Windows drive path: C:\..., D:\..., termasuk "C:folder\file"
    if ($t -match '^[A-Za-z]:') { return $false, $null, $false }
    # EXCLUDE UNC path: \\server\share atau //server/share
    if ($t -match '^(\\\\|//)') { return $false, $null, $false }

    # Detect URI scheme (ms-settings:, https:, mailto:, dll)
    # Negative lookahead cegah pola "scheme:\" atau "scheme:/"
    if ($t -match '^[a-z][a-z0-9+\.\-]*:(?![\\/])') {
        $scheme = ($t -split ':',2)[0]
        try {
            $exists = Test-Path -LiteralPath ("HKCR:\{0}" -f $scheme)
            return $true, $scheme, $exists
        } catch {
            return $true, $scheme, $false
        }
    }
    return $false, $null, $false
}

# -- Tulis ulang $apps ke $PROFILE (idempotent & multiline-safe) --
function Save-AppsToProfile {
    $appsBlock = @()
    $appsBlock += '# ===== Auto-generated apps dictionary ====='
    $appsBlock += '$global:apps = @{'
    foreach ($k in ($apps.Keys | Sort-Object)) {
        $appsBlock += "    `"$k`" = `"$($apps[$k])`""
    }
    $appsBlock += '}'
    $appsBlock += ''  # empty line

    $profilePath = $PROFILE
    $content = if (Test-Path $profilePath) { Get-Content $profilePath -Raw } else { "" }
    $newContent = $content -replace "(?s)# ===== Auto-generated apps dictionary =====.*?}\r?\n", ""
    $newContent = $newContent.Trim()
    if ($newContent.Length -gt 0) { $newContent += "`r`n" }
    $newContent += ($appsBlock -join "`r`n")
    $newContent | Set-Content $profilePath -Encoding UTF8
}

# ---- Helpers untuk validasi path/command ----
function Is-LikelyFilePath {
    param([string]$text)

    # URI? langsung bukan path
    $isUri, $scheme, $reg = Test-UriScheme $text
    if ($isUri) { return $false }

    # Path kalau:
    # - ada drive/UNC/dir separator, atau
    # - berakhiran exe/bat/cmd/lnk
    return (
        $text -match '^[A-Za-z]:|^(\\\\|//)|[\\/]' -or
        $text -match '\.(exe|bat|cmd|lnk)$'
    )
}

function Resolve-AppPath {
    param([string]$text)
    try {
        $isUri, $scheme, $reg = Test-UriScheme $text
        if ($isUri) { return $text } # URI tidak perlu resolve

        if (Is-LikelyFilePath $text) {
            $expanded = [Environment]::ExpandEnvironmentVariables($text)
            $resolved = Resolve-Path -LiteralPath $expanded -ErrorAction SilentlyContinue
            if ($resolved) { return $resolved.Path }
            return $expanded
        } else {
            # command sederhana ('calc', 'notepad', dll)
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
            Write-Verbose "URI scheme '$scheme' tidak terdaftar di HKCR (mungkin app pendukung belum terpasang)."
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

# === Tentukan Type (Exe/Command/URI) ===
function Get-AppType {
    param([string]$target)
    $isUri, $scheme, $reg = Test-UriScheme $target
    if ($isUri) { return "URI" }
    if (Is-LikelyFilePath $target) { return "Exe" }
    return "Command"
}

# ---------------- Colored ASCII Help Screen ----------------
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

# -- Launcher: open (with integrated help) --
function open {
    param([Parameter(Mandatory=$true, Position=0)][string]$app)

    $key = $app.ToLower()

    # HELP
    if ($key -in @('--help','-h','/h','help','/?')) { Show-LauncherHelp; return }

    if ($apps.ContainsKey($key)) {
        $target = Resolve-AppPath $apps[$key]
        if (-not (Test-AppTarget $target)) {
            Write-Warning "Target untuk '$key' tidak ditemukan/tidak tersedia: $target"
            Write-Output  "ℹ️  Update dengan: update-app `"$key`" `"<new-path-or-command>`""
            return
        }
        Write-Output "🚀 Launching $key ..."
        try { Start-Process $target } catch { Write-Error "Failed to start: $target" }
    } else {
        Write-Output "❌ App '$app' belum terdaftar."
        Write-Output "ℹ️  Lihat: list-apps   |   tambah cepat: register-app <name> <path>"
        Write-Output "ℹ️  Bantuan: open --help"
    }
}

# -- Register a new app --
function register-app {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)] [string]$name,
        [Parameter(Mandatory=$true, Position=1)] [string]$path,
        [switch]$Force,
        [switch]$DryRun
    )

    $lowerName = $name.ToLower()
    $resolved  = Resolve-AppPath $path
    $exists    = Test-AppTarget $resolved
    $already   = $apps.ContainsKey($lowerName)

    if (-not $exists -and -not $Force) {
        Write-Warning "Target tidak ditemukan/tidak tersedia: $path"
        Write-Output  "ℹ️  Jika yakin, jalankan ulang dengan -Force:"
        Write-Output  "    register-app `"$name`" `"$path`" -Force"
        return
    }

    if ($DryRun) {
        Write-Output "🔎 DRY-RUN: register-app"
        Write-Output "    Name  : $lowerName"
        if ($already) { Write-Output "    Old   : $($apps[$lowerName])" }
        Write-Output "    New   : $path"
        Write-Output "    File  : $PROFILE (unchanged)"
        if (-not $exists) { Write-Output "⚠️  Catatan: target belum terverifikasi (pakai -Force untuk bypass bila bukan dry-run)." }
        return
    }

    $apps[$lowerName] = $path
    Save-AppsToProfile

    if ($exists) {
        Write-Output "✅ Registered '$lowerName' → $path"
    } else {
        Write-Output "✅ Registered (forced) '$lowerName' → $path"
        Write-Output "⚠️  Catatan: target belum terverifikasi, pastikan path/command benar."
    }
    Write-Output "ℹ️  Cek dengan 'list-apps'."
}

# -- Remove an app --
function remove-app {
    param([Parameter(Mandatory=$true, Position=0)][string]$name)
    $lowerName = $name.ToLower()
    if ($apps.ContainsKey($lowerName)) {
        $apps.Remove($lowerName)
        Save-AppsToProfile
        Write-Output "🗑️  App '$lowerName' dihapus."
        Write-Output "ℹ️  Cek dengan 'list-apps'."
    } else {
        Write-Output "⚠️  App '$name' tidak ditemukan."
    }
}

# -- Update app path/command --
function update-app {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)] [string]$name,
        [Parameter(Mandatory=$true, Position=1)] [string]$newPath,
        [switch]$Force,
        [switch]$DryRun
    )

    $lowerName = $name.ToLower()
    if (-not $apps.ContainsKey($lowerName)) {
        Write-Output "⚠️  App '$name' belum terdaftar. Pakai:"
        Write-Output "    register-app `"$name`" `"$newPath`""
        return
    }

    $resolved = Resolve-AppPath $newPath
    $exists   = Test-AppTarget $resolved
    $oldPath  = $apps[$lowerName]

    if (-not $exists -and -not $Force) {
        Write-Warning "Target baru tidak ditemukan/tidak tersedia: $newPath"
        Write-Output  "ℹ️  Jika yakin, jalankan ulang dengan -Force:"
        Write-Output  "    update-app `"$name`" `"$newPath`" -Force"
        return
    }

    if ($DryRun) {
        Write-Output "🔎 DRY-RUN: update-app"
        Write-Output "    Name  : $lowerName"
        Write-Output "    Old   : $oldPath"
        Write-Output "    New   : $newPath"
        Write-Output "    File  : $PROFILE (unchanged)"
        if (-not $exists) { Write-Output "⚠️  Catatan: target baru belum terverifikasi (pakai -Force bila bukan dry-run)." }
        return
    }

    $apps[$lowerName] = $newPath
    Save-AppsToProfile

    Write-Output "🔁 Updated '$lowerName'"
    Write-Output "    Old → $oldPath"
    Write-Output "    New → $newPath"
    if (-not $exists) { Write-Output "⚠️  Catatan: perubahan dipaksa (target belum terverifikasi)." }
}

# ------------- Banner untuk list-apps -------------
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

# -- List apps (dengan kolom Type) --
function list-apps {
    param([string]$filter)

    $pairs = if ([string]::IsNullOrWhiteSpace($filter)) {
        $apps.GetEnumerator() | Sort-Object Key
    } else {
        $apps.GetEnumerator() | Where-Object { $_.Key -like "*$filter*" } | Sort-Object Key
    }

    Show-AppsBanner

    if (-not $pairs) {
        if ($filter) { Write-Host "No apps match filter: '$filter'." -ForegroundColor Yellow }
        else { Write-Host "No apps registered yet." -ForegroundColor Yellow }
        return
    }

    $rows = foreach ($p in $pairs) {
        [pscustomobject]@{
            Name = $p.Key
            Type = Get-AppType $p.Value
            Path = $p.Value
        }
    }

    $nameWidth = [Math]::Max(4, ($rows | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum)
    $typeWidth = [Math]::Max(4, ($rows | ForEach-Object { $_.Type.Length } | Measure-Object -Maximum).Maximum)
    $pathWidth = [Math]::Max(4, ($rows | ForEach-Object { $_.Path.Length } | Measure-Object -Maximum).Maximum)
    $totalWidth = $nameWidth + $typeWidth + $pathWidth + 8

    $hasAnsi = $PSStyle -ne $null
    if ($hasAnsi) {
        $c = [pscustomobject]@{
            box    = $PSStyle.Foreground.BrightBlack
            title  = $PSStyle.Foreground.BrightYellow + $PSStyle.Bold
            name   = $PSStyle.Foreground.BrightGreen
            type   = $PSStyle.Foreground.Magenta
            path   = $PSStyle.Foreground.BrightBlue
            dim    = $PSStyle.Foreground.BrightBlack
            cnt    = $PSStyle.Foreground.Cyan
            reset  = $PSStyle.Reset
        }

        $top    = $c.box + "+" + ("-" * ($totalWidth-2)) + "+" + $c.reset
        $hdrTxt = (" Name".PadRight($nameWidth) + " | " + "Type".PadRight($typeWidth) + " | " + "Path".PadRight($pathWidth))
        $hdr    = $c.box + "|" + $c.title + $hdrTxt + $c.reset + $c.box + "|" + $c.reset
        $sep    = $c.box + "+" + ("=" * ($totalWidth-2)) + "+" + $c.reset

        Write-Host $top
        Write-Host $hdr
        Write-Host $sep

        foreach ($r in $rows) {
            $name = $r.Name.PadRight($nameWidth)
            $type = $r.Type.PadRight($typeWidth)
            $path = $r.Path.PadRight($pathWidth)
            $line = $c.box + "|" + $c.name + $name + $c.reset + $c.box + " | " +
                    $c.type + $type + $c.reset + $c.box + " | " +
                    $c.path + $path + $c.reset + $c.box + "|" + $c.reset
            Write-Host $line
        }

        $bottom = $c.box + "+" + ("-" * ($totalWidth-2)) + "+" + $c.reset
        Write-Host $bottom
        Write-Host ($c.cnt + ("Total apps: {0}" -f ($rows.Count)) + $c.reset)
        if ($filter) { Write-Host ($c.dim + ("Filter: '{0}'" -f $filter) + $c.reset) }
    } else {
        $top    = "+" + ("-" * ($totalWidth-2)) + "+"
        $hdrTxt = (" Name".PadRight($nameWidth) + " | " + "Type".PadRight($typeWidth) + " | " + "Path".PadRight($pathWidth))
        $sep    = "+" + ("=" * ($totalWidth-2)) + "+"

        Write-Host $top -ForegroundColor DarkGray
        Write-Host ("|" + $hdrTxt + "|") -ForegroundColor Yellow
        Write-Host $sep -ForegroundColor DarkGray

        foreach ($r in $rows) {
            $name = $r.Name.PadRight($nameWidth)
            $type = $r.Type.PadRight($typeWidth)
            $path = $r.Path.PadRight($pathWidth)
            Write-Host ("|" + $name + " | " + $type + " | " + $path + "|")
        }

        Write-Host ("+" + ("-" * ($totalWidth-2)) + "+") -ForegroundColor DarkGray
        Write-Host ("Total apps: {0}" -f ($rows.Count)) -ForegroundColor Cyan
        if ($filter) { Write-Host ("Filter: '{0}'" -f $filter) -ForegroundColor DarkGray }
    }
}

# -- Startup Message --
Write-Output "ℹ️  Main Command: open <name>, register-app, update-app, remove-app, list-apps"
Write-Output "ℹ️  Complete Help: open --help"

# ================= Aliases =================
Set-Alias o        open
Set-Alias regapp   register-app
Set-Alias updapp   update-app
Set-Alias rmapp    remove-app
function apps { param([string]$filter) if ($PSBoundParameters.ContainsKey('filter') -and $null -ne $filter -and $filter.Trim().Length -gt 0) { list-apps $filter } elseif ($args.Count -gt 0) { list-apps $args[0] } else { list-apps } }
Set-Alias la apps

# =====================================================================
# ===== Auto-generated apps dictionary =====
# (Bagian ini otomatis di-maintain oleh Save-AppsToProfile)
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
