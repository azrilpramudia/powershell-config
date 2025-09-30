# ============= Prompt, modul, dan preferensi =============
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

# Alias umum
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

# -- Seed dictionary global (akan ditimpa blok auto-generated di bawah) --
if (-not (Get-Variable apps -Scope Global -ErrorAction SilentlyContinue)) {
    $global:apps = @{
        "chrome"  = "C:\Program Files\Google\Chrome\Application\chrome.exe"
        "vscode"  = "C:\Users\Azril\AppData\Local\Programs\Microsoft VS Code\Code.exe"
        "spotify" = "C:\Users\Azril\AppData\Roaming\Spotify\Spotify.exe"
        "notepad" = "notepad"
        "calc"    = "calc"
    }
}

# -- Helper: tulis blok $apps ke $PROFILE (idempotent & aman multiline) --
function Save-AppsToProfile {
    # Susun blok $apps
    $appsBlock = @()
    $appsBlock += '# ===== Auto-generated apps dictionary ====='
    $appsBlock += '$global:apps = @{'
    foreach ($k in ($apps.Keys | Sort-Object)) {
        $appsBlock += "    `"$k`" = `"$($apps[$k])`""
    }
    $appsBlock += '}'
    $appsBlock += ''  # baris kosong

    # Baca profil saat ini (raw agar newline tidak berubah)
    $profilePath = $PROFILE
    $content = if (Test-Path $profilePath) { Get-Content $profilePath -Raw } else { "" }

    # Hapus blok lama (jika ada), regex single-line (?s) supaya .* mencakup newline
    $newContent = $content -replace "(?s)# ===== Auto-generated apps dictionary =====.*?}\r?\n", ""

    # Tambahkan blok baru di akhir
    $newContent = $newContent.Trim()
    if ($newContent.Length -gt 0) { $newContent += "`r`n" }
    $newContent += ($appsBlock -join "`r`n")

    # Simpan kembali
    $newContent | Set-Content $profilePath -Encoding UTF8
}

# ---- Helpers validasi path/command ----
function Is-LikelyFilePath {
    param([string]$text)
    # Path jika mengandung drive/sep atau berakhiran .exe/.bat/.cmd
    return ($text -match '[:\\/]' -or $text -match '\.(exe|bat|cmd)$')
}

function Resolve-AppPath {
    param([string]$text)
    try {
        if (Is-LikelyFilePath $text) {
            $expanded = [Environment]::ExpandEnvironmentVariables($text)
            $resolved = Resolve-Path -LiteralPath $expanded -ErrorAction SilentlyContinue
            if ($resolved) { return $resolved.Path }
            return $expanded
        } else {
            # command seperti 'calc', 'notepad', dll
            return $text
        }
    } catch {
        return $text
    }
}

function Test-AppTarget {
    param([string]$target)
    if (Is-LikelyFilePath $target) {
        $expanded = [Environment]::ExpandEnvironmentVariables($target)
        return (Test-Path -LiteralPath $expanded)
    } else {
        return [bool](Get-Command -Name $target -ErrorAction SilentlyContinue)
    }
}

# -- Launcher: open (dengan help terintegrasi) --
function open {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$app
    )

    $key = $app.ToLower()

    # ===== HELP MODE =====
    if ($key -in @('--help','-h','/h','help','/?')) {
        Write-Output ""
        Write-Output "📘 PowerShell App Launcher – Ringkasan Perintah"
        Write-Output "----------------------------------------------"
        Write-Output "open <name>                  → Buka aplikasi"
        Write-Output "register-app <n> <p>         → Daftar aplikasi baru"
        Write-Output "   -Force, -DryRun           → Validasi opsional"
        Write-Output "update-app <n> <p>           → Perbarui path aplikasi"
        Write-Output "   -Force, -DryRun           → Validasi opsional"
        Write-Output "remove-app <name>            → Hapus aplikasi dari daftar"
        Write-Output "list-apps [filter]           → Lihat daftar aplikasi"
        Write-Output ""
        Write-Output "Alias cepat:"
        Write-Output "  o, regapp, updapp, rmapp, apps / la"
        Write-Output ""
        Write-Output "Contoh:"
        Write-Output "  open vscode"
        Write-Output "  regapp store ms-windows-store:"
        Write-Output "  updapp vscode 'C:\Path\baru\Code.exe'"
        Write-Output "  rmapp store"
        Write-Output "  apps ms"
        Write-Output ""
        return
    }

    if ($apps.ContainsKey($key)) {
        $target = Resolve-AppPath $apps[$key]
        if (-not (Test-AppTarget $target)) {
            Write-Warning "Target untuk '$key' tidak ditemukan/command tidak tersedia: $target"
            Write-Output  "ℹ️  Perbarui dengan: update-app `"$key`" `"<path/command-baru>`""
            return
        }
        Write-Output "🚀 Membuka $key ..."
        try { Start-Process $target } catch { Write-Error "Gagal menjalankan: $target" }
    } else {
        Write-Output "❌ Aplikasi '$app' belum diregister di command 'open'."
        Write-Output "ℹ️  Cek daftar: list-apps   |   daftar cepat: register-app <name> <path>"
        Write-Output "ℹ️  Bantuan: open --help"
    }
}

# -- Register aplikasi baru (validasi + -Force + -DryRun) --
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
        Write-Warning "Target tidak ditemukan/command tidak tersedia: $path"
        Write-Output  "ℹ️  Jika yakin benar, jalankan lagi dengan -Force:"
        Write-Output  "    register-app `"$name`" `"$path`" -Force"
        return
    }

    if ($DryRun) {
        if ($already) {
            Write-Output "🔎 DRY-RUN: register-app"
            Write-Output "    Name  : $lowerName"
            Write-Output "    Old   : $($apps[$lowerName])"
            Write-Output "    New   : $path"
            Write-Output "    File  : $PROFILE (tidak diubah)"
        } else {
            Write-Output "🔎 DRY-RUN: register-app"
            Write-Output "    Name  : $lowerName"
            Write-Output "    New   : $path"
            Write-Output "    File  : $PROFILE (tidak diubah)"
        }
        if (-not $exists) {
            Write-Output "⚠️  Catatan: target belum terverifikasi ada (gunakan -Force untuk melewati validasi saat bukan dry-run)."
        }
        return
    }

    # Tulis perubahan (bukan dry-run)
    $apps[$lowerName] = $path  # simpan sesuai input user
    Save-AppsToProfile

    if ($exists) {
        Write-Output "✅ Registered '$lowerName' → $path"
    } else {
        Write-Output "✅ Registered (forced) '$lowerName' → $path"
        Write-Output "⚠️  Catatan: target belum terverifikasi ada. Pastikan path/command benar."
    }
    Write-Output "ℹ️  Gunakan 'list-apps' untuk verifikasi."
}

# -- Hapus aplikasi --
function remove-app {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$name
    )
    $lowerName = $name.ToLower()
    if ($apps.ContainsKey($lowerName)) {
        $apps.Remove($lowerName)
        Save-AppsToProfile
        Write-Output "🗑️  Aplikasi '$lowerName' berhasil dihapus."
        Write-Output "ℹ️  Gunakan 'list-apps' untuk verifikasi."
    } else {
        Write-Output "⚠️  Aplikasi '$name' tidak ditemukan di daftar."
    }
}

# -- Update path aplikasi (validasi + -Force + -DryRun) --
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
        Write-Output "⚠️  Aplikasi '$name' belum terdaftar. Gunakan:"
        Write-Output "    register-app `"$name`" `"$newPath`""
        return
    }

    $resolved = Resolve-AppPath $newPath
    $exists   = Test-AppTarget $resolved
    $oldPath  = $apps[$lowerName]

    if (-not $exists -and -not $Force) {
        Write-Warning "Target baru tidak ditemukan/command tidak tersedia: $newPath"
        Write-Output  "ℹ️  Jika yakin benar, jalankan lagi dengan -Force:"
        Write-Output  "    update-app `"$name`" `"$newPath`" -Force"
        return
    }

    if ($DryRun) {
        Write-Output "🔎 DRY-RUN: update-app"
        Write-Output "    Name  : $lowerName"
        Write-Output "    Old   : $oldPath"
        Write-Output "    New   : $newPath"
        Write-Output "    File  : $PROFILE (tidak diubah)"
        if (-not $exists) {
            Write-Output "⚠️  Catatan: target baru belum terverifikasi ada (gunakan -Force untuk melewati validasi saat bukan dry-run)."
        }
        return
    }

    # Tulis perubahan (bukan dry-run)
    $apps[$lowerName] = $newPath
    Save-AppsToProfile

    Write-Output "🔁 Updated '$lowerName'"
    Write-Output "    Old → $oldPath"
    Write-Output "    New → $newPath"
    if (-not $exists) {
        Write-Output "⚠️  Catatan: target baru belum terverifikasi ada (forced)."
    }
}

# -- List aplikasi --
function list-apps {
    param([string]$filter)

    $pairs = if ([string]::IsNullOrWhiteSpace($filter)) {
        $apps.GetEnumerator() | Sort-Object Key
    } else {
        $apps.GetEnumerator() | Where-Object { $_.Key -like "*$filter*" } | Sort-Object Key
    }

    if (-not $pairs) {
        if ($filter) {
            Write-Output "⚠️  Tidak ada aplikasi yang cocok filter: '$filter'."
        } else {
            Write-Output "⚠️  Belum ada aplikasi yang terdaftar."
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
# Write-Output "✅ Please registered this application on PowerShell command profile:"
# $apps.Keys | Sort-Object | ForEach-Object { Write-Output "   - $_" }
Write-Output "ℹ️  Main Command: open <name>, register-app, update-app, remove-app, list-apps"
Write-Output "ℹ️  Complete Help: open --help"

# ================= Aliases & Autocomplete =================

# Aliases pendek
Set-Alias o        open
Set-Alias regapp   register-app
Set-Alias updapp   update-app
Set-Alias rmapp    remove-app
# 'apps' kita override biar bisa forward filter otomatis
Set-Alias la       list-apps

# Alias fungsi 'apps' yang auto-forward filter
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

# ---------- Fuzzy Autocomplete Helpers ----------
# Subsequence tester (untuk fuzzy)
if (-not (Get-Command Test-Subsequence -ErrorAction SilentlyContinue)) {
    function Test-Subsequence {
        param([string]$Text, [string]$Pattern)
        if ([string]::IsNullOrWhiteSpace($Pattern)) { return $true, 0 }
        $i = 0; $j = 0; $gaps = 0
        $t = $Text.ToLower(); $p = $Pattern.ToLower()
        while ($i -lt $t.Length -and $j -lt $p.Length) {
            if ($t[$i] -eq $p[$j]) { $j++ } else { $gaps++ }
            $i++
        }
        return ($j -eq $p.Length), $gaps
    }
}

function Complete-AppNameFuzzy {
    param([string]$wordToComplete)

    $term = "$wordToComplete"
    $keys = $apps.Keys

    $scored = foreach ($k in $keys) {
        $kl = $k.ToLower()
        $score = $null
        if ($term.Length -eq 0) {
            $score = 0
        }
        elseif ($kl.StartsWith($term.ToLower())) {
            $score = 0 + ($kl.Length - $term.Length)         # terbaik: prefix
        }
        elseif ($kl -like "*$term*") {
            $idx = $kl.IndexOf($term.ToLower())
            $score = 100 + $idx + ($kl.Length - $term.Length) # tengah: contains
        }
        else {
            $ok,$gaps = Test-Subsequence -Text $kl -Pattern $term.ToLower()
            if ($ok) { $score = 200 + $gaps + [math]::Abs($kl.Length - $term.Length) } # fallback: subsequence
        }
        if ($null -ne $score) { [pscustomobject]@{ Key=$k; Score=$score } }
    }

    foreach ($c in ($scored | Sort-Object Score, { $_.Key.Length }, Key | Select-Object -First 30)) {
        [System.Management.Automation.CompletionResult]::new($c.Key, $c.Key, 'ParameterValue', $c.Key)
    }
}

# ---- Autocomplete untuk 'apps' (parameter filter) - fuzzy ----
Register-ArgumentCompleter -CommandName apps -ParameterName filter -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    Complete-AppNameFuzzy -wordToComplete $wordToComplete
}

# ---- Autocomplete nama aplikasi untuk 'open' (fuzzy) ----
Register-ArgumentCompleter -CommandName open -ParameterName app -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    Complete-AppNameFuzzy -wordToComplete $wordToComplete
}

# ---- Autocomplete nama aplikasi untuk 'update-app' & 'remove-app' (fuzzy) ----
Register-ArgumentCompleter -CommandName update-app -ParameterName name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    Complete-AppNameFuzzy -wordToComplete $wordToComplete
}
Register-ArgumentCompleter -CommandName remove-app -ParameterName name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    Complete-AppNameFuzzy -wordToComplete $wordToComplete
}
# dukung alias
Register-ArgumentCompleter -CommandName updapp -ParameterName name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    Complete-AppNameFuzzy -wordToComplete $wordToComplete
}
Register-ArgumentCompleter -CommandName rmapp -ParameterName name -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    Complete-AppNameFuzzy -wordToComplete $wordToComplete
}

# ---- Autocomplete untuk flags Force/DryRun ----
Register-ArgumentCompleter -CommandName register-app -ParameterName Force -ScriptBlock {
    [System.Management.Automation.CompletionResult]::new('-Force','-Force','ParameterName','Force register even if path not found')
}
Register-ArgumentCompleter -CommandName update-app -ParameterName Force -ScriptBlock {
    [System.Management.Automation.CompletionResult]::new('-Force','-Force','ParameterName','Force update even if path not found')
}
Register-ArgumentCompleter -CommandName register-app -ParameterName DryRun -ScriptBlock {
    [System.Management.Automation.CompletionResult]::new('-DryRun','-DryRun','ParameterName','Preview without writing profile')
}
Register-ArgumentCompleter -CommandName update-app -ParameterName DryRun -ScriptBlock {
    [System.Management.Automation.CompletionResult]::new('-DryRun','-DryRun','ParameterName','Preview without writing profile')
}

# =====================================================================
# ===== Auto-generated apps dictionary =====
# (Bagian ini di-maintain otomatis oleh Save-AppsToProfile)
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
