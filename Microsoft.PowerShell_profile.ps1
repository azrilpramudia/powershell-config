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

# Force Fastfetch to use YOUR config every time (bypass path confusion)
if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
    fastfetch -c "C:/Users/azril/.config/fastfetch/config.jsonc"
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
    if ($t -match "^[A-Za-z]:") { return $false, $null, $false }
    # EXCLUDE UNC path: \\server\share atau //server/share
    if ($t -match "^(\\\\|//)") { return $false, $null, $false }

    # Detect URI scheme (ms-settings:, https:, mailto:, dll)
    # Negative lookahead cegah pola "scheme:\" atau "scheme:/"
    if ($t -match "^[a-z][a-z0-9+\.\-]*:(?![\\/])") {
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
    # Susun blok auto-generated
    $appsBlock = @()
    $appsBlock += '# ===== Auto-generated apps dictionary ====='
    $appsBlock += '$global:apps = @{'
    foreach ($k in ($apps.Keys | Sort-Object)) {
        $appsBlock += "    `"$k`" = `"$($apps[$k])`""
    }
    $appsBlock += '}'

    $profilePath = $PROFILE
    $content = if (Test-Path $profilePath) { Get-Content $profilePath -Raw } else { "" }

    # Cari blok lama & replace (atau append kalau belum ada)
    $pattern = "(?s)# ===== Auto-generated apps dictionary =====.*?\}"
    if ($content -match $pattern) {
        $newContent = [regex]::Replace($content, $pattern, ($appsBlock -join "`r`n"))
    } else {
        $trimmed = $content.TrimEnd()
        if ($trimmed.Length -gt 0) { $trimmed += "`r`n`r`n" }
        $newContent = $trimmed + ($appsBlock -join "`r`n")
    }

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
        ($text -match "^[A-Za-z]:") -or
        ($text -match "^(\\\\|//)") -or
        ($text -match "[\\/]") -or
        ($text -match "\.(exe|bat|cmd|lnk)$")
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
        @{ text = "open <name>                  → Launch a registered app"; style = "cmd"   }
        @{ text = "register-app <n> <p>         → Register a new app path/command"; style = "cmd" }
        @{ text = "update-app <n> <p>           → Update an app path/command"; style = "cmd" }
        @{ text = "remove-app <name>            → Remove an app from registry"; style = "cmd" }
        @{ text = "list-apps [filter]           → Show all registered apps"; style = "cmd" }
        @{ text = ""; style = "" }
        @{ text = "Media Commands:"; style = "title2" }
        @{ text = "  play-video <path> [options]  → Open video file(s) or URL"; style = "cmd" }
        @{ text = "    -With <app>               → Use a specific player (e.g. vlc)"; style = "dim" }
        @{ text = "    -Recurse                  → Include subfolders when using patterns"; style = "dim" }
        @{ text = ""; style = "" }
        @{ text = "Quick aliases:"; style = "title2" }
        @{ text = "  o, regapp, updapp, rmapp, apps / la, play"; style = "cmd" }
        @{ text = ""; style = "" }
        @{ text = "Examples:"; style = "title2" }
        @{ text = "  open vscode"; style = "ex" }
        @{ text = "  regapp store ms-windows-store:"; style = "ex" }
        @{ text = "  updapp vscode 'C:\\New\\Path\\Code.exe'"; style = "ex" }
        @{ text = "  rmapp store"; style = "ex" }
        @{ text = "  apps ms"; style = "ex" }
        @{ text = ""; style = "" }
        @{ text = "Multimedia Examples:"; style = "title2" }
        @{ text = "  play 'D:\\Videos\\demo.mp4'"; style = "ex" }
        @{ text = "  play *.mp4 -Recurse"; style = "ex" }
        @{ text = "  play https://youtu.be/dQw4w9WgXcQ"; style = "ex" }
        @{ text = "  play trailer.mkv -With vlc"; style = "ex" }
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
        Write-Host "open <name>                  → Launch a registered app" -ForegroundColor Green
        Write-Host "register-app <n> <p>         → Register a new app path/command" -ForegroundColor Green
        Write-Host "update-app <n> <p>           → Update an app path/command" -ForegroundColor Green
        Write-Host "remove-app <name>            → Remove an app from registry" -ForegroundColor Green
        Write-Host "list-apps [filter]           → Show all registered apps" -ForegroundColor Green
        Write-Host ""
        Write-Host "Media Commands:" -ForegroundColor Yellow
        Write-Host "  play-video <path> [options]  → Open video file(s) or URL" -ForegroundColor Green
        Write-Host "    -With <app>               → Use a specific player (e.g. vlc)" -ForegroundColor DarkGray
        Write-Host "    -Recurse                  → Include subfolders when using patterns" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "Quick aliases:" -ForegroundColor Yellow
        Write-Host "  o, regapp, updapp, rmapp, apps / la, play" -ForegroundColor Green
        Write-Host ""
        Write-Host "Examples:" -ForegroundColor Yellow
        Write-Host "  open vscode" -ForegroundColor Blue
        Write-Host "  regapp store ms-windows-store:" -ForegroundColor Blue
        Write-Host "  updapp vscode 'C:\\New\\Path\\Code.exe'" -ForegroundColor Blue
        Write-Host "  rmapp store" -ForegroundColor Blue
        Write-Host "  apps ms" -ForegroundColor Blue
        Write-Host ""
        Write-Host "Multimedia Examples:" -ForegroundColor Yellow
        Write-Host "  play 'D:\\Videos\\demo.mp4'" -ForegroundColor Blue
        Write-Host "  play *.mp4 -Recurse" -ForegroundColor Blue
        Write-Host "  play https://youtu.be/dQw4w9WgXcQ" -ForegroundColor Blue
        Write-Host "  play trailer.mkv -With vlc" -ForegroundColor Blue
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

# ===================== Play Video =====================
# Ekstensi video umum
$global:VideoExtensions = @('.mp4','.mkv','.avi','.mov','.webm','.m4v','.wmv','.flv','.3gp','.m2ts','.mpg','.mpeg')

function Test-IsVideoExtension {
    param([string]$PathOrName)
    $ext = [System.IO.Path]::GetExtension($PathOrName)
    return $global:VideoExtensions -contains ($ext.ToLower())
}

function play-video {
    <#
    .SYNOPSIS
      Buka video/file/URL dari PowerShell.

    .EXAMPLES
      play-video "D:\Movies\Interstellar.mkv"
      play-video *.mp4
      play-video "D:\Clips\*.mp4" -Recurse
      play-video https://youtu.be/dQw4w9WgXcQ
      play-video .\trailer.mp4 -With vlc       # player dari registry $apps
      play-video *.mkv -With "C:\Program Files\VideoLAN\VLC\vlc.exe"

    .PARAMETER Path
      File/Pattern/URL. Bisa banyak argumen.

    .PARAMETER With
      Nama app di $apps (atau path exe) untuk memaksa player tertentu.

    .PARAMETER Recurse
      Cari video di subfolder saat pattern dipakai.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromRemainingArguments=$true, Position=0)]
        [string[]]$Path,
        [string]$With,
        [switch]$Recurse
    )

    # Resolve player (optional)
    $player = $null
    if ($PSBoundParameters.ContainsKey('With') -and -not [string]::IsNullOrWhiteSpace($With)) {
        $key = $With.ToLower()
        if ($apps.ContainsKey($key)) {
            $player = Resolve-AppPath $apps[$key]
        } else {
            # Kalau user kasih path langsung ke exe
            $player = Resolve-AppPath $With
        }
        if (-not (Test-AppTarget $player)) {
            Write-Warning "Player '$With' tidak ditemukan/tersedia. Pakai default app saja."
            $player = $null
        }
    }

    $opened = 0
    foreach ($p in $Path) {
        $p = [Environment]::ExpandEnvironmentVariables($p)

        # URL? (http/https atau custom scheme)
        $isUri, $scheme, $reg = Test-UriScheme $p
        if ($isUri -or $p -match "^(http|https)://") {
            if ($player) {
                try { Start-Process -FilePath $player -ArgumentList @($p) ; $opened++ }
                catch { Write-Error "Gagal membuka URL dengan player: $p" }
            } else {
                try { Start-Process $p ; $opened++ }
                catch { Write-Error "Gagal membuka URL: $p" }
            }
            continue
        }

        # Pattern / Path
        $items = @()
        try {
            # Gunakan -ErrorAction untuk pattern yang tidak match
            $gciParams = @{
                Path = $p
                File = $true
                ErrorAction = 'SilentlyContinue'
            }
            if ($Recurse) { $gciParams['Recurse'] = $true }
            $items = Get-ChildItem @gciParams
            if (-not $items -and (Test-Path -LiteralPath $p -PathType Leaf)) {
                # literal exact file
                $items = ,(Get-Item -LiteralPath $p)
            }
        } catch {}

        if (-not $items) {
            Write-Warning "Tidak ditemukan: $p"
            continue
        }

        foreach ($it in $items) {
            # filter hanya video (kalau bukan video tapi user ingin paksa, hapus kondisi ini)
            if (-not (Test-IsVideoExtension $it.Name)) {
                Write-Verbose "Skip (bukan video): $($it.FullName)"
                continue
            }

            try {
                if ($player) {
                    Start-Process -FilePath $player -ArgumentList @("`"$($it.FullName)`"")
                } else {
                    # Default app Windows untuk ekstensi tsb
                    Invoke-Item -LiteralPath $it.FullName
                }
                $opened++
            } catch {
                Write-Error "Gagal membuka: $($it.FullName)"
            }
        }
    }

    if ($opened -gt 0) {
        Write-Host "🎬 Opened $opened item(s)." -ForegroundColor Cyan
    } else {
        Write-Host "⚠️  Tidak ada video yang dibuka." -ForegroundColor Yellow
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
Set-Alias play play-video

# =====================================================================
# =====================================================================
# ===== Auto-generated apps dictionary =====
$global:apps = @{
    "arduino" = "C:\Program Files\Arduino IDE\Arduino IDE.exe"
    "calc" = "calc"
    "chrome" = "C:\Program Files\Google\Chrome\Application\chrome.exe"
    "discord" = "C:\Users\azril\AppData\Local\Discord\app-1.0.9210\Discord.exe"
    "explorer" = "C:\Windows\explorer.exe"
    "godot" = "C:\Program Files\Godot_v4.4.1\Godot_v4.4.1-stable_mono_win64.exe"
    "msedge" = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    "msexcel" = "C:\Program Files\Microsoft Office\root\Office16\EXCEL.exe"
    "mspoint" = "C:\Program Files\Microsoft Office\root\Office16\POWERPNT.exe"
    "msword" = "C:\Program Files\Microsoft Office\root\Office16\WINWORD.exe"
    "notepad" = "notepad"
    "notepad++" = "C:\Program Files\Notepad++\notepad++.exe"
    "paint" = "mspaint"
    "pcsx2" = "C:\Users\azril\Documents\pcsx2-v2.3.88-windows-x64-Qt\pcsx2-qt.exe"
    "postman" = "C:\Users\azril\AppData\Local\Postman\Postman.exe"
    "spotify" = "C:\Users\Azril\AppData\Roaming\Spotify\Spotify.exe"
    "steam" = "C:\Program Files (x86)\Steam\steam.exe"
    "vbox" = "C:\Program Files\Oracle\VirtualBox\VirtualBox.exe"
    "vlc" = "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
    "vscode" = "C:\Users\Azril\AppData\Local\Programs\Microsoft VS Code\Code.exe"
}

