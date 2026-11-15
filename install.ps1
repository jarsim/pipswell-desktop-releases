# Pipswell Desktop installer (Windows 10/11, PowerShell 5.1 or 7):
#
#     irm https://raw.githubusercontent.com/jarsim/pipswell-desktop-releases/main/install.ps1 | iex
#
# Idempotent: running it again IS the update (same steps, newest release, jobs restarted).
# Nothing outside %LOCALAPPDATA%\Pipswell, the user Path and the Start Menu / Desktop shortcuts that
# `pipswell setup` makes is touched; no administrator rights are needed.
#
#   PIPSWELL_RELEASES_URL   where latest-windows-x64.txt, the zip and its .sha256 live (https, or http://127.0.0.1 for tests)
#   PIPSWELL_HOME           install somewhere else than %LOCALAPPDATA%\Pipswell
#
# This file is pure ASCII on purpose: `irm` of a file with a byte order mark or a code page the
# console does not read breaks the parse. Everything runs inside one function and failures are
# `throw`n, never `exit`: under `| iex` an exit would close the buyer's PowerShell window.

function Install-Pipswell {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        # PowerShell 7 already negotiates TLS 1.2 or newer
        $null = $_
    }

    # The releases repo (jarsim/pipswell-desktop-releases). PIPSWELL_RELEASES_URL overrides the address.
    $DEFAULT_RELEASES_URL = 'https://github.com/jarsim/pipswell-desktop-releases/releases/latest/download'
    # uv is fetched from Astral at this exact version; keep it equal to UV_VERSION in install.sh.
    # UV_WIN_SHA256 is the SHA256 of that version's uv-x86_64-pc-windows-msvc.zip (from its .sha256 asset).
    $UV_VERSION = '0.11.6'
    $UV_WIN_SHA256 = '99aa60edd017a256dbf378f372d1cff3292dbc6696e0ea01716d9158d773ab77'
    $PYTHON_VERSION = '3.13'
    $MT5_PAGE = 'https://www.metatrader5.com/en/download'
    $MT5_SETUP = 'https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe'

    function Say([string]$Text) { Write-Host $Text }

    # A native command that fails stops the install (PowerShell does not do that by itself).
    function Invoke-Native([string]$Exe, [string[]]$Arguments, [string]$What) {
        & $Exe @Arguments
        if ($LASTEXITCODE -ne 0) { throw "$What failed (exit code $LASTEXITCODE)." }
    }

    # Remove a directory JUNCTION without touching what it points to. Never Remove-Item -Recurse on a
    # junction: Windows PowerShell 5.1 can delete the TARGET's contents. Directory.Delete on the link
    # path (not recursive) removes only the link.
    function Remove-Junction([string]$Path) {
        if (-not (Test-Path -LiteralPath $Path)) { return }
        $item = Get-Item -LiteralPath $Path -Force
        if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "$Path is a real folder, not a link; it is not removed. Move it away and run the command again."
        }
        [IO.Directory]::Delete($Path)
    }

    function Get-Download([string]$Url, [string]$OutFile, [bool]$AllowLoopbackHttp) {
        $resp = Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $OutFile -PassThru
        # a redirect may lead to https only
        $final = $null
        if ($resp.BaseResponse.ResponseUri) { $final = $resp.BaseResponse.ResponseUri }
        elseif ($resp.BaseResponse.RequestMessage) { $final = $resp.BaseResponse.RequestMessage.RequestUri }
        if ($final -and $final.Scheme -ne 'https') {
            $loopback = $AllowLoopbackHttp -and $final.Scheme -eq 'http' -and $final.Host -eq '127.0.0.1'
            if (-not $loopback) {
                Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
                throw "The download of $Url was redirected to a non-https address."
            }
        }
    }

    function Get-Sha256([string]$File) {
        return (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    # ---- this machine ---------------------------------------------------------------------------
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'Pipswell Desktop runs on Windows 10 or 11 (this is not Windows).' }
    if ([Environment]::OSVersion.Version.Major -lt 10) { throw 'Pipswell Desktop needs Windows 10 or 11.' }
    if (-not [Environment]::Is64BitOperatingSystem) { throw 'Pipswell Desktop needs a 64-bit Windows.' }
    $arch = $env:PROCESSOR_ARCHITEW6432
    if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
    if ($arch -eq 'ARM64') {
        Say 'Note: this is an ARM64 PC. Pipswell and MetaTrader run as x64 programs under Windows emulation.'
    }

    $releasesUrl = $env:PIPSWELL_RELEASES_URL
    if (-not $releasesUrl) { $releasesUrl = $DEFAULT_RELEASES_URL }
    $releasesUrl = $releasesUrl.TrimEnd('/')
    if ($releasesUrl -like '*<OWNER>*') {
        throw 'The releases address still has the <OWNER> placeholder. Set PIPSWELL_RELEASES_URL to the real address.'
    }
    # Parsed, not prefix-matched: https://host/... without credentials, or plain http for the exact host
    # 127.0.0.1 only (a local test server). http://127.0.0.1.evil.example begins like an allowed address.
    $urlMatch = [regex]::Match($releasesUrl, '^(https|http)://([^/?#@\s]+)(/\S*)?$')
    if (-not $urlMatch.Success) { throw 'PIPSWELL_RELEASES_URL must be an https:// address (no credentials).' }
    $urlScheme = $urlMatch.Groups[1].Value
    $urlHost = ($urlMatch.Groups[2].Value -split ':')[0]
    $loopbackHttp = $false
    if ($urlScheme -eq 'http') {
        if ($urlHost -ne '127.0.0.1') { throw 'PIPSWELL_RELEASES_URL must be an https:// address.' }
        $loopbackHttp = $true
    }

    $homeDir = $env:PIPSWELL_HOME
    $customHome = [bool]$homeDir
    if (-not $homeDir) {
        if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is not set.' }
        $homeDir = Join-Path $env:LOCALAPPDATA 'Pipswell'
    }
    $appRoot = Join-Path $homeDir 'app'
    $binDir = Join-Path $appRoot 'bin'
    $uv = Join-Path $binDir 'uv.exe'
    $cli = Join-Path $binDir 'pipswell.cmd'

    # ---- MetaTrader 5: the first install found, in the order Pipswell setup uses ---------------------
    function Get-TerminalFolder([string]$Candidate) {
        if (-not $Candidate) { return $null }
        $c = $Candidate.Trim().Trim('"')
        if (-not $c) { return $null }
        if (Test-Path -LiteralPath $c -PathType Leaf) {
            if ((Split-Path -Leaf $c) -ieq 'terminal64.exe') { return (Split-Path -Parent $c) }
            return $null
        }
        if (Test-Path -LiteralPath (Join-Path $c 'terminal64.exe') -PathType Leaf) { return $c }
        return $null
    }

    function Find-MetaTrader {
        $homeFull = [IO.Path]::GetFullPath($homeDir).TrimEnd('\')
        $own = { param($p) $p -and ([IO.Path]::GetFullPath($p).TrimEnd('\') + '\').StartsWith($homeFull + '\', [StringComparison]::OrdinalIgnoreCase) }
        # 1. MT5_SOURCE in pipswell.env
        $envFile = Join-Path $homeDir 'pipswell.env'
        if (Test-Path -LiteralPath $envFile -PathType Leaf) {
            foreach ($line in (Get-Content -LiteralPath $envFile -ErrorAction SilentlyContinue)) {
                if ($line -match '^\s*MT5_SOURCE\s*=\s*(.+?)\s*$') {
                    $f = Get-TerminalFolder $Matches[1]
                    if ($f) { return $f }
                }
            }
        }
        # 2. the default install folder
        if ($env:ProgramFiles) {
            $f = Get-TerminalFolder (Join-Path $env:ProgramFiles 'MetaTrader 5')
            if ($f) { return $f }
        }
        # 3. the install a data folder points to (origin.txt is UTF-16)
        if ($env:APPDATA) {
            $terms = Join-Path $env:APPDATA 'MetaQuotes\Terminal'
            if (Test-Path -LiteralPath $terms -PathType Container) {
                foreach ($origin in (Get-ChildItem -LiteralPath $terms -Directory -ErrorAction SilentlyContinue)) {
                    $of = Join-Path $origin.FullName 'origin.txt'
                    if (-not (Test-Path -LiteralPath $of -PathType Leaf)) { continue }
                    try { $text = (Get-Content -LiteralPath $of -Encoding Unicode -TotalCount 1) } catch { continue }
                    $f = Get-TerminalFolder $text
                    if ($f -and -not (& $own $f)) { return $f }
                }
            }
        }
        # 4. any program folder holding a terminal64.exe
        if ($env:ProgramFiles -and (Test-Path -LiteralPath $env:ProgramFiles -PathType Container)) {
            foreach ($dir in (Get-ChildItem -LiteralPath $env:ProgramFiles -Directory -ErrorAction SilentlyContinue)) {
                $f = Get-TerminalFolder $dir.FullName
                if ($f -and -not (& $own $f)) { return $f }
            }
        }
        # 5. the uninstall registry
        $keys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        foreach ($key in $keys) {
            try { $entries = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue } catch { continue }
            foreach ($e in $entries) {
                if ($e.DisplayName -like '*MetaTrader 5*' -and $e.InstallLocation) {
                    $f = Get-TerminalFolder $e.InstallLocation
                    if ($f -and -not (& $own $f)) { return $f }
                }
            }
        }
        return $null
    }

    $mt5 = Find-MetaTrader
    if (-not $mt5) {
        throw @"
MetaTrader 5 is not installed.

  1. Download it:  $MT5_SETUP
     (download page: $MT5_PAGE)
  2. Install it, start it and log in to your account once.
  3. Run this command again.
"@
    }
    Say "MetaTrader 5 found: $mt5"

    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    # The folder holds secrets (ADMIN_TOKEN, BRIDGE_SECRET, ledgers): this user, SYSTEM and Administrators
    # only, inheritance removed. A failure is a warning, not a reason to stop the install.
    try {
        $userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        & icacls $homeDir /inheritance:r /grant:r "*${userSid}:(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "icacls exited with code $LASTEXITCODE" }
    } catch {
        Say "Warning: could not restrict access to $homeDir ($($_.Exception.Message)). Check its permissions by hand."
    }
    # uv keeps Python, its cache and any Python links in the app folder: nothing to clean up elsewhere.
    $env:UV_PYTHON_INSTALL_DIR = Join-Path $appRoot 'python'
    $env:UV_CACHE_DIR = Join-Path $appRoot 'uv-cache'
    $env:UV_PYTHON_BIN_DIR = $binDir
    $env:UV_NO_MODIFY_PATH = '1'

    $work = Join-Path ([IO.Path]::GetTempPath()) ('pipswell-install-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    try {
        # ---- uv, into the app folder only ---------------------------------------------------------
        if (-not (Test-Path -LiteralPath $uv -PathType Leaf)) {
            Say "Installing uv $UV_VERSION into $binDir ..."
            $uvZip = Join-Path $work 'uv.zip'
            Get-Download "https://github.com/astral-sh/uv/releases/download/$UV_VERSION/uv-x86_64-pc-windows-msvc.zip" $uvZip $false
            if ((Get-Sha256 $uvZip) -ne $UV_WIN_SHA256) { throw 'The uv download does not match its pinned SHA256. Nothing was run.' }
            $uvOut = Join-Path $work 'uv-x'
            Expand-Archive -LiteralPath $uvZip -DestinationPath $uvOut -Force
            $found = Get-ChildItem -LiteralPath $uvOut -Recurse -Filter 'uv.exe' | Select-Object -First 1
            if (-not $found) { throw 'uv.exe is not in the uv download.' }
            foreach ($name in 'uv.exe', 'uvx.exe') {
                $src = Join-Path $found.DirectoryName $name
                if (Test-Path -LiteralPath $src -PathType Leaf) { Copy-Item -LiteralPath $src -Destination $binDir -Force }
            }
            if (-not (Test-Path -LiteralPath $uv -PathType Leaf)) { throw "uv did not install into $binDir." }
        }
        Say "Python $PYTHON_VERSION ..."
        Invoke-Native $uv @('python', 'install', $PYTHON_VERSION) 'Installing Python'

        # ---- the release: version, file and hash come from latest-windows-x64.txt (the compiled
        # Windows build); the zip must match them -----
        Say 'Looking for the newest release ...'
        $platform = 'windows-x64'
        $latestName = "latest-$platform.txt"
        $latest = Join-Path $work $latestName
        try { Get-Download "$releasesUrl/$latestName" $latest $loopbackHttp } catch { throw "Could not read $releasesUrl/$latestName" }
        $line = (Get-Content -LiteralPath $latest -TotalCount 1)
        $parts = @(([string]$line).Trim() -split '\s+')
        if ($parts.Count -lt 3) { throw "${latestName}: expected `"<version> <file> <sha256>`"." }
        $version = $parts[0]; $file = $parts[1]; $sha = $parts[2]
        if ($version -notmatch '^[0-9]+(\.[0-9]+){1,3}([-+.][0-9A-Za-z.]+)?$') { throw "${latestName}: bad version." }
        if ($file -cne "pipswell-desktop-$version-$platform.zip") { throw "${latestName}: bad file name." }
        if ($sha -cnotmatch '^[0-9a-f]{64}$') { throw "${latestName}: bad SHA256." }

        $target = Join-Path $appRoot $version
        if (Test-Path -LiteralPath (Join-Path $target '.installed') -PathType Leaf) {
            Say "Pipswell $version is already unpacked."
        } else {
            Say "Downloading Pipswell $version ..."
            $zip = Join-Path $work $file
            $side = Join-Path $work "$file.sha256"
            Get-Download "$releasesUrl/$file" $zip $loopbackHttp
            Get-Download "$releasesUrl/$file.sha256" $side $loopbackHttp
            $got = Get-Sha256 $zip
            $sideSha = (([string](Get-Content -LiteralPath $side -TotalCount 1)).Trim() -split '\s+')[0].ToLowerInvariant()
            if ($got -ne $sha) { throw "The download does not match the SHA256 in $latestName. Nothing was installed." }
            if ($sideSha -ne $sha) { throw "$file.sha256 disagrees with $latestName. Nothing was installed." }
            Say 'SHA256 verified.'

            # Unpack with the checks `pipswell update` applies (pipswell/updater.py extract): no symlink,
            # no absolute path, no `..`, exactly one top-level folder. Mirrors updater.extract and the
            # extract step of install.sh; the hash above already says the zip is the published one.
            $extractPy = Join-Path $work 'extract.py'
            $py = @'
import stat, sys, zipfile
from pathlib import Path

zip_path, dest = sys.argv[1], Path(sys.argv[2])
with zipfile.ZipFile(zip_path) as z:
    infos = z.infolist()
    if not infos:
        sys.exit("the release zip is empty")
    if len({i.filename.split("/", 1)[0] for i in infos}) != 1:
        sys.exit("the release zip must have exactly one top-level folder")
    for i in infos:
        # ':' is a drive ("C:/x", "top/D:/x") or an NTFS stream: an escape from dest on Windows
        if (i.filename.startswith(("/", "\\")) or ".." in Path(i.filename).parts or "\\" in i.filename
                or ":" in i.filename):
            sys.exit(f"unsafe path in the release zip: {i.filename}")
        if stat.S_ISLNK(i.external_attr >> 16):
            sys.exit(f"symlink in the release zip: {i.filename}")
    dest.mkdir(parents=True, exist_ok=False)
    for i in infos:
        target = dest / i.filename
        if not target.resolve().is_relative_to(dest.resolve()):
            sys.exit(f"unsafe path in the release zip: {i.filename}")
        if i.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(z.read(i))
        target.chmod(0o755 if (i.external_attr >> 16) & 0o100 else 0o644)
'@
            [IO.File]::WriteAllText($extractPy, $py, (New-Object Text.UTF8Encoding($false)))
            $unpacked = Join-Path $work 'x'
            try {
                Invoke-Native $uv @('run', '--no-project', '--python', $PYTHON_VERSION, 'python', '-I', $extractPy, $zip, $unpacked) 'Unpacking'
            } catch {
                throw 'The release zip failed the safety checks. Nothing was installed.'
            }
            $top = Join-Path $unpacked "pipswell-desktop-$version"
            if (-not (Test-Path -LiteralPath $top -PathType Container)) { throw 'Unexpected release layout.' }
            if (Test-Path -LiteralPath $target) {
                $existing = Get-Item -LiteralPath $target -Force
                if ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    [IO.Directory]::Delete($target)
                } else {
                    Remove-Item -LiteralPath $target -Recurse -Force
                }
            }
            Move-Item -LiteralPath $top -Destination $target
            Say 'Installing the Python packages (locked versions) ...'
            try {
                Invoke-Native $uv @('sync', '--frozen', '--no-dev', '--python', $PYTHON_VERSION, '--project', $target) 'uv sync'
            } catch {
                Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
                throw 'uv sync failed; the previous version (if any) is untouched.'
            }
            New-Item -ItemType File -Force -Path (Join-Path $target '.installed') | Out-Null
        }

        # ---- switch to it: one directory junction, replaced in two quick steps ----------------------
        # (a symlink needs administrator rights; a junction does not)
        $current = Join-Path $appRoot 'current'
        $staging = Join-Path $appRoot '.current.new'
        Remove-Junction $staging
        New-Item -ItemType Junction -Path $staging -Target $target | Out-Null
        Remove-Junction $current
        [IO.Directory]::Move($staging, $current)

        # ---- the `pipswell` command: a tiny wrapper, so updates never leave it pointing at old code --
        # -I: isolated mode (no current folder, no PYTHON* variables, no user site on sys.path)
        $lines = @('@echo off', 'rem written by the Pipswell installer')
        if ($customHome) { $lines += ('set "PIPSWELL_HOME=' + $homeDir.Replace('%', '%%') + '"') }
        $lines += ('"' + (Join-Path $current '.venv\Scripts\python.exe').Replace('%', '%%') + '" -X utf8 -I -m pipswell %*')
        # cmd reads the file in the OEM code page; a user name with accents must survive
        try {
            $enc = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
        } catch {
            $enc = [Text.Encoding]::ASCII
        }
        [IO.File]::WriteAllText("$cli.new", (($lines -join "`r`n") + "`r`n"), $enc)
        Move-Item -LiteralPath "$cli.new" -Destination $cli -Force

        # ---- app\bin on the user Path (registry value kept REG_EXPAND_SZ) and in this session -------
        $envKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
        try {
            $userPath = [string]$envKey.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $have = @($userPath -split ';' | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') })
            if ($have -inotcontains $binDir.TrimEnd('\')) {
                $newPath = if ($userPath) { $userPath.TrimEnd(';') + ';' + $binDir } else { $binDir }
                $envKey.SetValue('Path', $newPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
                # setting and clearing a user variable through .NET broadcasts "environment changed", so
                # new terminals see the Path without a logout
                [Environment]::SetEnvironmentVariable('PIPSWELL_PATH_REFRESH', '1', 'User')
                [Environment]::SetEnvironmentVariable('PIPSWELL_PATH_REFRESH', $null, 'User')
            }
        } finally {
            $envKey.Close()
        }
        if (($env:Path -split ';') -inotcontains $binDir) { $env:Path = "$binDir;$env:Path" }

        # ---- set up, (re)start, open --------------------------------------------------------------
        Invoke-Native $cli @('setup') 'pipswell setup'
        Invoke-Native $cli @('restart') 'pipswell restart'
        & $cli open
        if ($LASTEXITCODE -ne 0) { Say 'Note: the Pipswell window did not open; run  pipswell open  in a moment.' }
        Say ''
        Say "Pipswell $version is running. Everything is DRY: nothing real is placed until you switch it off yourself."
        Say '  pipswell status    pipswell doctor    pipswell stop    pipswell update    pipswell uninstall'
        Say '  (open a NEW terminal window for the pipswell command to be found)'
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

try {
    Install-Pipswell
} catch {
    Write-Host ''
    Write-Host ('Pipswell install failed: ' + $_.Exception.Message) -ForegroundColor Red
    $global:LASTEXITCODE = 1
}
