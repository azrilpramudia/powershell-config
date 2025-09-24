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

# Alias
Set-Alias -Name vim -Value nvim

# Import the Chocolatey Profile that contains the necessary code to enable
# tab-completions to function for `choco`.
# Be aware that if you are missing these lines from your profile, tab completion
# for `choco` will not function.
# See https://ch0.co/tab-completion for details.
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

# -- Launcher: open --
function open {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$app
    )

    $key = $app.ToLower()

    if ($key -eq "--help") {
        Write-Output "📖 Help: PowerShell App Launcher"
        Write-Output "--------------------------------"
        Write-Output "open <name>             → Membuka aplikasi"
        Write-Output "register-app <n> <p>    → Daftarkan aplikasi baru"
        Write-Output "remove-app <name>       → Hapus aplikasi dari daftar"
        Write-Output "update-app <n> <p>      → Perbarui path aplikasi"
        Write-Output "list-apps [filter]      → Lihat aplikasi yang terdaftar"
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
        Write-Output "ℹ️  Cek daftar dengan: list-apps"
    }
}

# -- Register aplikasi baru (validasi + -Force) --
function register-app {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$name,
        [Parameter(Mandatory=$true, Position=1)]
        [string]$path,
        [switch]$Force
    )

    $lowerName = $name.ToLower()
    $resolved  = Resolve-AppPath $path
    $exists    = Test-AppTarget $resolved

    if (-not $exists -and -not $Force) {
        Write-Warning "Target tidak ditemukan/command tidak tersedia: $path"
        Write-Output  "ℹ️  Jika yakin benar, jalankan lagi dengan -Force:"
        Write-Output  "    register-app `"$name`" `"$path`" -Force"
        return
    }

    $apps[$lowerName] = $path   # simpan sesuai input user
    Save-AppsToProfile

    if ($exists) {
        Write-Output "✅ Registered '$lowerName' → $path"
    } else {
        Write-Output "✅ Registered (forced) '$lowerName' → $path"
        Write-Output "⚠️  Catatan: saat ini target belum terverifikasi ada. Pastikan path/command benar."
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

# -- Update path aplikasi (validasi + -Force) --
function update-app {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$name,
        [Parameter(Mandatory=$true, Position=1)]
        [string]$newPath,
        [switch]$Force
    )

    $lowerName = $name.ToLower()
    if (-not $apps.ContainsKey($lowerName)) {
        Write-Output "⚠️  Aplikasi '$name' belum terdaftar. Gunakan:"
        Write-Output "    register-app `"$name`" `"$newPath`""
        return
    }

    $resolved = Resolve-AppPath $newPath
    $exists   = Test-AppTarget $resolved

    if (-not $exists -and -not $Force) {
        Write-Warning "Target baru tidak ditemukan/command tidak tersedia: $newPath"
        Write-Output  "ℹ️  Jika yakin benar, jalankan lagi dengan -Force:"
        Write-Output  "    update-app `"$name`" `"$newPath`" -Force"
        return
    }

    $oldPath = $apps[$lowerName]
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

# -- Pesan startup --
Write-Output "✅ Please registered this application on PowerShell command profile:"
$apps.Keys | Sort-Object | ForEach-Object { Write-Output "   - $_" }
Write-Output "ℹ️  Perintah: open <name>, register-app <name> <path> [-Force], remove-app <name>, update-app <name> <path> [-Force], list-apps [filter], open --help"

# =====================================================================
# ===== Auto-generated apps dictionary =====
# (Bagian ini di-maintain otomatis oleh Save-AppsToProfile)
$global:apps = @{
    "arduino"   = "C:\Program Files\Arduino IDE\Arduino IDE.exe"
    "calc"      = "calc"
    "chrome"    = "C:\Program Files\Google\Chrome\Application\chrome.exe"
    "discord"   = "C:\Users\azril\AppData\Local\Discord\app-1.0.9209\Discord.exe"
    "godot"     = "C:\Program Files\Godot_v4.4.1\Godot_v4.4.1-stable_mono_win64.exe"
    "msedge"    = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    "msexcel"   = "C:\Program Files\Microsoft Office\root\Office16\EXCEL.exe"
    "mspoint"   = "C:\Program Files\Microsoft Office\root\Office16\POWERPNT.exe"
    "msword"    = "C:\Program Files\Microsoft Office\root\Office16\WINWORD.exe"
    "notepad"   = "notepad"
    "notepad++" = "C:\Program Files\Notepad++\notepad++.exe"
    "pcsx2"     = "C:\Users\azril\Documents\pcsx2-v2.3.88-windows-x64-Qt\pcsx2-qt.exe"
    "postman"   = "C:\Users\azril\AppData\Local\Postman\Postman.exe"
    "spotify"   = "C:\Users\Azril\AppData\Roaming\Spotify\Spotify.exe"
    "steam"     = "C:\Program Files (x86)\Steam\steam.exe"
    "vbox"      = "C:\Program Files\Oracle\VirtualBox\VirtualBox.exe"
    "vlc"       = "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"
    "vscode"    = "C:\Users\Azril\AppData\Local\Programs\Microsoft VS Code\Code.exe"
}
# =====================================================================