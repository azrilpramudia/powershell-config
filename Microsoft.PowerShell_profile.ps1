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

# ===== PowerShell App Launcher =====
# Fitur: open, register-app, remove-app, update-app, list-apps

# -- Inisialisasi dictionary global --
if (-not (Get-Variable apps -Scope Global -ErrorAction SilentlyContinue)) {
    $global:apps = @{
        "chrome"  = "C:\Program Files\Google\Chrome\Application\chrome.exe"
        "vscode"  = "C:\Users\Azril\AppData\Local\Programs\Microsoft VS Code\Code.exe"
        "spotify" = "C:\Users\Azril\AppData\Roaming\Spotify\Spotify.exe"
        "notepad" = "notepad"
        "calc"    = "calc"
    }
}

# -- Helper: simpan blok $apps ke $PROFILE (idempotent) --
function Save-AppsToProfile {
    # Bangun ulang isi $apps sebagai string berblok
    $appsBlock = @()
    $appsBlock += '# ===== Auto-generated apps dictionary ====='
    $appsBlock += '$global:apps = @{'
    foreach ($k in ($apps.Keys | Sort-Object)) {
        $appsBlock += "    `"$k`" = `"$($apps[$k])`""
    }
    $appsBlock += '}'
    $appsBlock += ''

    # Baca & update profile
    $profilePath = $PROFILE
    $content = if (Test-Path $profilePath) { Get-Content $profilePath -Raw } else { "" }

    # Hapus blok lama (jika ada), lalu sisip blok baru di akhir
    $newContent = $content -replace '(?s)# ===== Auto-generated apps dictionary =====.*?}\r?\n', ''
    $newContent = $newContent.Trim()
    if ($newContent.Length -gt 0) { $newContent += "`r`n" }
    $newContent += ($appsBlock -join "`r`n")

    $newContent | Set-Content $profilePath -Encoding UTF8
}

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
        $path = $apps[$key]
        Write-Output "🚀 Membuka $key ..."
        Start-Process $path
    } else {
        Write-Output "❌ Aplikasi '$app' belum diregister di command 'open'."
        Write-Output "ℹ️ Cek daftar dengan: list-apps"
    }
}

function register-app {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$name,
        [Parameter(Mandatory=$true, Position=1)]
        [string]$path
    )
    $lowerName = $name.ToLower()
    $apps[$lowerName] = $path
    Save-AppsToProfile
    Write-Output "✅ Registered '$lowerName' → $path"
    Write-Output "ℹ️ Gunakan 'list-apps' untuk verifikasi."
}

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

function update-app {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$name,
        [Parameter(Mandatory=$true, Position=1)]
        [string]$newPath
    )
    $lowerName = $name.ToLower()
    if ($apps.ContainsKey($lowerName)) {
        $oldPath = $apps[$lowerName]
        $apps[$lowerName] = $newPath
        Save-AppsToProfile
        Write-Output "🔁 Updated '$lowerName'"
        Write-Output "    Old → $oldPath"
        Write-Output "    New → $newPath"
    } else {
        Write-Output "⚠️  Aplikasi '$name' belum terdaftar. Gunakan 'register-app ""$name"" ""$newPath""'."
    }
}

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

# ===== Info saat PowerShell dibuka =====
Write-Output "✅ Please registered this application on PowerShell command profile:"
$apps.Keys | Sort-Object | ForEach-Object { Write-Output "   - $_" }
Write-Output "ℹ️  Perintah: open <name>, register-app <name> <path>, remove-app <name>, update-app <name> <path>, list-apps [filter], open --help"
