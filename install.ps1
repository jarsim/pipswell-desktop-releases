# Pipswell Desktop installer (Windows 10/11, PowerShell 5.1 or 7):
#
#     irm https://raw.githubusercontent.com/jarsim/pipswell-desktop-releases/main/install.ps1 | iex
#
# Idempotent: running it again IS the update (same steps, newest release, jobs restarted).
# Nothing outside %LOCALAPPDATA%\Pipswell, the user Path and the Start Menu / Desktop shortcuts that
# `pipswell setup` makes is touched; no administrator rights are needed.
#
#   PIPSWELL_RELEASES_URL   where latest-windows-x64.txt, its .sig, the zip and its .sha256 live (https, or http://127.0.0.1 for tests)
#   PIPSWELL_CHANNEL        beta: the newest beta (vX.Y.ZbN, vX.Y.Z.devN); unset or stable: stable releases only
#
# The release list (latest-windows-x64.txt) is used only after its Ed25519 signature (<file>.sig, made offline by the
# owner) verifies against $releaseKey below. .NET Framework (Windows PowerShell 5.1) has no Ed25519, so the check runs
# in the Python this installer installs (standard library only), before anything of the release is used.
#   PIPSWELL_HOME           install somewhere else than %LOCALAPPDATA%\Pipswell
#   PIPSWELL_LANG           sk, cz or en: the language of the messages (default: the Windows display language: Slovak, Czech, else English)
#
# This file is pure ASCII on purpose: `irm` of a file with a byte order mark or a code page the
# console does not read breaks the parse. Everything runs inside one function and failures are
# `throw`n, never `exit`: under `| iex` an exit would close the buyer's PowerShell window.

function Install-Pipswell {
    param([string]$FailureMessage)

    # ---- messages (begin): every line the user reads. One table, the same keys and texts as install.sh (tests/test_installer_lang.py
    # compares them). `lang|key|text`: lang en, sk or cz; \n is a line break; \uXXXX is a character (decoded with [regex]::Unescape at
    # run time, so this file stays pure ASCII); {name} is filled by Get-PipswellMessage. Keys with win_ exist only here.
    # Output goes through Write-Host, which the Windows PowerShell 5.1 and 7 consoles write as Unicode whatever [Console]::OutputEncoding is,
    # so the encoding of the console is not touched.

    # The language of the messages from PIPSWELL_LANG ($Override: sk, cz or en; any other value is ignored), else the Windows display language
    # ($UiCode, the two-letter code), else the regional format ($CultureCode): sk is Slovak, cs is Czech (cz), anything else English.
    function Resolve-PipswellLanguage([string]$Override, [string]$UiCode, [string]$CultureCode) {
        if ($Override -ceq 'sk' -or $Override -ceq 'cz' -or $Override -ceq 'en') { return $Override }
        $code = ([string]$UiCode).Trim().ToLowerInvariant()
        if (-not $code -or $code -eq 'iv') { $code = ([string]$CultureCode).Trim().ToLowerInvariant() }
        if ($code -eq 'sk') { return 'sk' }
        if ($code -eq 'cs') { return 'cz' }
        return 'en'
    }

    function Get-PipswellLanguage {
        $ui = ''
        $culture = ''
        try { $ui = [string](Get-UICulture).TwoLetterISOLanguageName } catch { $null = $_ }
        try { $culture = [string](Get-Culture).TwoLetterISOLanguageName } catch { $null = $_ }
        return Resolve-PipswellLanguage $env:PIPSWELL_LANG $ui $culture
    }

    # The text of $Key in $Lang (English when it has none), \n and \uXXXX decoded, each {name} filled from $Values once, left to
    # right (a value is never searched for further names).
    function Get-PipswellMessage([string]$Key, [string]$Lang, [hashtable]$Values) {
        $table = @'
en|channel_stored_bad|{file} must say stable or beta, not {value}
sk|channel_stored_bad|{file} mus\u00ed obsahova\u0165 stable alebo beta, nie {value}
cz|channel_stored_bad|{file} mus\u00ed obsahovat stable nebo beta, ne {value}

en|channel_env_bad|PIPSWELL_CHANNEL must be stable or beta, not {value}
sk|channel_env_bad|PIPSWELL_CHANNEL mus\u00ed by\u0165 stable alebo beta, nie {value}
cz|channel_env_bad|PIPSWELL_CHANNEL mus\u00ed b\u00fdt stable nebo beta, ne {value}

en|url_not_https_creds|PIPSWELL_RELEASES_URL must be an https:// address (no credentials).
sk|url_not_https_creds|PIPSWELL_RELEASES_URL mus\u00ed by\u0165 adresa https:// (bez prihlasovac\u00edch \u00fadajov).
cz|url_not_https_creds|PIPSWELL_RELEASES_URL mus\u00ed b\u00fdt adresa https:// (bez p\u0159ihla\u0161ovac\u00edch \u00fadaj\u016f).

en|url_not_https|PIPSWELL_RELEASES_URL must be an https:// address.
sk|url_not_https|PIPSWELL_RELEASES_URL mus\u00ed by\u0165 adresa https://.
cz|url_not_https|PIPSWELL_RELEASES_URL mus\u00ed b\u00fdt adresa https://.

en|key_none|This installer carries no release signing key yet, so it cannot verify a release. Nothing was installed or changed.
sk|key_none|Tento in\u0161tal\u00e1tor zatia\u013e nem\u00e1 podpisov\u00fd k\u013e\u00fa\u010d vydan\u00ed, tak\u017ee nem\u00f4\u017ee overi\u0165 vydanie. Ni\u010d sa nenain\u0161talovalo ani nezmenilo.
cz|key_none|Tento instal\u00e1tor zat\u00edm nem\u00e1 podpisov\u00fd kl\u00ed\u010d vyd\u00e1n\u00ed, tak\u017ee nem\u016f\u017ee ov\u011b\u0159it vyd\u00e1n\u00ed. Nic se nenainstalovalo ani nezm\u011bnilo.

en|key_bad|The release signing key in this installer is malformed. Nothing was installed or changed.
sk|key_bad|Podpisov\u00fd k\u013e\u00fa\u010d vydan\u00ed v tomto in\u0161tal\u00e1tore je po\u0161koden\u00fd. Ni\u010d sa nenain\u0161talovalo ani nezmenilo.
cz|key_bad|Podpisov\u00fd kl\u00ed\u010d vyd\u00e1n\u00ed v tomto instal\u00e1toru je po\u0161kozen\u00fd. Nic se nenainstalovalo ani nezm\u011bnilo.

en|no_python|No Python found to verify the release signature. Nothing was installed.
sk|no_python|Nena\u0161iel sa Python na overenie podpisu vydania. Ni\u010d sa nenain\u0161talovalo.
cz|no_python|Nena\u0161el se Python pro ov\u011b\u0159en\u00ed podpisu vyd\u00e1n\u00ed. Nic se nenainstalovalo.

en|python_foreign|The Python found for the signature check ({python}) is not the one this installer installed. Nothing was installed.
sk|python_foreign|Python n\u00e1jden\u00fd na overenie podpisu ({python}) nie je ten, ktor\u00fd nain\u0161taloval tento in\u0161tal\u00e1tor. Ni\u010d sa nenain\u0161talovalo.
cz|python_foreign|Python nalezen\u00fd pro ov\u011b\u0159en\u00ed podpisu ({python}) nen\u00ed ten, kter\u00fd nainstaloval tento instal\u00e1tor. Nic se nenainstalovalo.

en|sig_invalid|{name} is not signed by the Pipswell release key. Nothing was installed or changed.
sk|sig_invalid|{name} nie je podp\u00edsan\u00fd vydavate\u013esk\u00fdm k\u013e\u00fa\u010dom Pipswell. Ni\u010d sa nenain\u0161talovalo ani nezmenilo.
cz|sig_invalid|{name} nen\u00ed podepsan\u00fd vydavatelsk\u00fdm kl\u00ed\u010dem Pipswell. Nic se nenainstalovalo ani nezm\u011bnilo.

en|pointer_unreadable|Could not read {url}
sk|pointer_unreadable|Nepodarilo sa pre\u010d\u00edta\u0165 {url}
cz|pointer_unreadable|Nepoda\u0159ilo se p\u0159e\u010d\u00edst {url}

en|pointer_no_sig|{name} has no signature ({url}.sig could not be read): this release is not signed. Nothing was installed or changed.
sk|pointer_no_sig|{name} nem\u00e1 podpis ({url}.sig sa nepodarilo pre\u010d\u00edta\u0165): toto vydanie nie je podp\u00edsan\u00e9. Ni\u010d sa nenain\u0161talovalo ani nezmenilo.
cz|pointer_no_sig|{name} nem\u00e1 podpis ({url}.sig se nepoda\u0159ilo p\u0159e\u010d\u00edst): toto vyd\u00e1n\u00ed nen\u00ed podepsan\u00e9. Nic se nenainstalovalo ani nezm\u011bnilo.

en|installing_uv|Installing uv {version} into {dir} ...
sk|installing_uv|In\u0161talujem uv {version} do {dir} ...
cz|installing_uv|Instaluji uv {version} do {dir} ...

en|uv_not_installed|uv did not install into {dir}.
sk|uv_not_installed|uv sa nenain\u0161taloval do {dir}.
cz|uv_not_installed|uv se nenainstaloval do {dir}.

en|python_step|Python {version} ...
sk|python_step|Python {version} ...
cz|python_step|Python {version} ...

en|looking_release|Looking for the newest release ({channel}) ...
sk|looking_release|H\u013ead\u00e1m najnov\u0161ie vydanie ({channel}) ...
cz|looking_release|Hled\u00e1m nejnov\u011bj\u0161\u00ed vyd\u00e1n\u00ed ({channel}) ...

en|bad_version|{name}: bad version.
sk|bad_version|{name}: neplatn\u00e1 verzia.
cz|bad_version|{name}: neplatn\u00e1 verze.

en|bad_file|{name}: bad file name.
sk|bad_file|{name}: neplatn\u00fd n\u00e1zov s\u00faboru.
cz|bad_file|{name}: neplatn\u00fd n\u00e1zev souboru.

en|bad_sha|{name}: bad SHA256.
sk|bad_sha|{name}: neplatn\u00fd SHA256.
cz|bad_sha|{name}: neplatn\u00fd SHA256.

en|stable_refuses|{name} offers {version}, a beta or dev build: the stable channel does not take it. Nothing was installed or changed.
sk|stable_refuses|{name} pon\u00faka {version}, \u010do je beta alebo v\u00fdvojov\u00e1 zostava: stabiln\u00fd kan\u00e1l ju neprij\u00edma. Ni\u010d sa nenain\u0161talovalo ani nezmenilo.
cz|stable_refuses|{name} nab\u00edz\u00ed {version}, co\u017e je beta nebo v\u00fdvojov\u00e9 sestaven\u00ed: stabiln\u00ed kan\u00e1l ho nep\u0159ij\u00edm\u00e1. Nic se nenainstalovalo ani nezm\u011bnilo.

en|already_unpacked|Pipswell {version} is already unpacked.
sk|already_unpacked|Pipswell {version} je u\u017e rozbalen\u00fd.
cz|already_unpacked|Pipswell {version} je u\u017e rozbalen\u00fd.

en|downloading|Downloading Pipswell {version} ...
sk|downloading|S\u0165ahujem Pipswell {version} ...
cz|downloading|Stahuji Pipswell {version} ...

en|sha_mismatch|The download does not match the SHA256 in {name}. Nothing was installed.
sk|sha_mismatch|Stiahnut\u00fd s\u00fabor nezodpoved\u00e1 SHA256 v {name}. Ni\u010d sa nenain\u0161talovalo.
cz|sha_mismatch|Sta\u017een\u00fd soubor neodpov\u00edd\u00e1 SHA256 v {name}. Nic se nenainstalovalo.

en|sha_side|{file}.sha256 disagrees with {name}. Nothing was installed.
sk|sha_side|{file}.sha256 sa nezhoduje s {name}. Ni\u010d sa nenain\u0161talovalo.
cz|sha_side|{file}.sha256 se neshoduje s {name}. Nic se nenainstalovalo.

en|sha_verified|SHA256 verified.
sk|sha_verified|SHA256 overen\u00fd.
cz|sha_verified|SHA256 ov\u011b\u0159en.

en|zip_unsafe|The release zip failed the safety checks. Nothing was installed.
sk|zip_unsafe|Arch\u00edv vydania nepre\u0161iel bezpe\u010dnostn\u00fdmi kontrolami. Ni\u010d sa nenain\u0161talovalo.
cz|zip_unsafe|Archiv vyd\u00e1n\u00ed nepro\u0161el bezpe\u010dnostn\u00edmi kontrolami. Nic se nenainstalovalo.

en|layout_bad|Unexpected release layout.
sk|layout_bad|Neo\u010dak\u00e1van\u00e1 \u0161trukt\u00fara vydania.
cz|layout_bad|Neo\u010dek\u00e1van\u00e1 struktura vyd\u00e1n\u00ed.

en|installing_packages|Installing the Python packages (locked versions) ...
sk|installing_packages|In\u0161talujem bal\u00edky Pythonu (zamknut\u00e9 verzie) ...
cz|installing_packages|Instaluji bal\u00ed\u010dky Pythonu (zam\u010den\u00e9 verze) ...

en|sync_failed|uv sync failed; the previous version (if any) is untouched.
sk|sync_failed|uv sync zlyhal; predch\u00e1dzaj\u00faca verzia (ak nejak\u00e1 je) zostala nedotknut\u00e1.
cz|sync_failed|uv sync selhal; p\u0159edchoz\u00ed verze (pokud n\u011bjak\u00e1 je) z\u016fstala nedot\u010den\u00e1.

en|running|Pipswell {version} is running. Everything is DRY: nothing real is placed until you switch it off yourself.
sk|running|Pipswell {version} be\u017e\u00ed. V\u0161etko je v testovacom re\u017eime (DRY): ni\u010d sa naozaj neotvor\u00ed, k\u00fdm ho s\u00e1m nevypne\u0161.
cz|running|Pipswell {version} b\u011b\u017e\u00ed. V\u0161echno je v testovac\u00edm re\u017eimu (DRY): nic se doopravdy neotev\u0159e, dokud ho s\u00e1m nevypne\u0161.

en|win_not_windows|Pipswell Desktop runs on Windows 10 or 11 (this is not Windows).
sk|win_not_windows|Pipswell Desktop be\u017e\u00ed na Windows 10 alebo 11 (toto nie je Windows).
cz|win_not_windows|Pipswell Desktop b\u011b\u017e\u00ed na Windows 10 nebo 11 (toto nen\u00ed Windows).

en|win_old_windows|Pipswell Desktop needs Windows 10 or 11.
sk|win_old_windows|Pipswell Desktop potrebuje Windows 10 alebo 11.
cz|win_old_windows|Pipswell Desktop pot\u0159ebuje Windows 10 nebo 11.

en|win_not_64bit|Pipswell Desktop needs a 64-bit Windows.
sk|win_not_64bit|Pipswell Desktop potrebuje 64-bitov\u00fd Windows.
cz|win_not_64bit|Pipswell Desktop pot\u0159ebuje 64bitov\u00fd Windows.

en|win_arm_note|Note: this is an ARM64 PC. Pipswell and MetaTrader run as x64 programs under Windows emulation.
sk|win_arm_note|Pozn\u00e1mka: toto je po\u010d\u00edta\u010d s ARM64. Pipswell a MetaTrader tu be\u017eia ako programy x64 v emul\u00e1cii Windows.
cz|win_arm_note|Pozn\u00e1mka: toto je po\u010d\u00edta\u010d s ARM64. Pipswell a MetaTrader zde b\u011b\u017e\u00ed jako programy x64 v emulaci Windows.

en|win_no_localappdata|LOCALAPPDATA is not set.
sk|win_no_localappdata|Premenn\u00e1 LOCALAPPDATA nie je nastaven\u00e1.
cz|win_no_localappdata|Prom\u011bnn\u00e1 LOCALAPPDATA nen\u00ed nastaven\u00e1.

en|win_owner_placeholder|The releases address still has the <OWNER> placeholder. Set PIPSWELL_RELEASES_URL to the real address.
sk|win_owner_placeholder|Adresa vydan\u00ed e\u0161te obsahuje z\u00e1stupn\u00fd text <OWNER>. Nastav PIPSWELL_RELEASES_URL na skuto\u010dn\u00fa adresu.
cz|win_owner_placeholder|Adresa vyd\u00e1n\u00ed je\u0161t\u011b obsahuje z\u00e1stupn\u00fd text <OWNER>. Nastav PIPSWELL_RELEASES_URL na skute\u010dnou adresu.

en|win_mt5_found|MetaTrader 5 found: {path}
sk|win_mt5_found|MetaTrader 5 n\u00e1jden\u00fd: {path}
cz|win_mt5_found|MetaTrader 5 nalezen: {path}

en|win_mt5_missing|MetaTrader 5 is not installed.\n\n  1. Download it:  {setup}\n     (download page: {page})\n  2. Install it, start it and log in to your account once.\n  3. Run this command again.
sk|win_mt5_missing|MetaTrader 5 nie je nain\u0161talovan\u00fd.\n\n  1. Stiahni ho:  {setup}\n     (str\u00e1nka na stiahnutie: {page})\n  2. Nain\u0161taluj ho, spusti ho a raz sa prihl\u00e1s do svojho \u00fa\u010dtu.\n  3. Spusti tento pr\u00edkaz znova.
cz|win_mt5_missing|MetaTrader 5 nen\u00ed nainstalovan\u00fd.\n\n  1. St\u00e1hni si ho:  {setup}\n     (str\u00e1nka ke sta\u017een\u00ed: {page})\n  2. Nainstaluj ho, spus\u0165 ho a jednou se p\u0159ihlas ke sv\u00e9mu \u00fa\u010dtu.\n  3. Spus\u0165 tento p\u0159\u00edkaz znovu.

en|win_uv_sha|The uv download does not match its pinned SHA256. Nothing was run.
sk|win_uv_sha|Stiahnut\u00fd s\u00fabor uv nezodpoved\u00e1 o\u010dak\u00e1van\u00e9mu SHA256. Ni\u010d sa nespustilo.
cz|win_uv_sha|Sta\u017een\u00fd soubor uv neodpov\u00edd\u00e1 o\u010dek\u00e1van\u00e9mu SHA256. Nic se nespustilo.

en|win_uv_exe_missing|uv.exe is not in the uv download.
sk|win_uv_exe_missing|uv.exe nie je v stiahnutom s\u00fabore uv.
cz|win_uv_exe_missing|uv.exe nen\u00ed ve sta\u017een\u00e9m souboru uv.

en|win_pointer_format|{name}: expected "<version> <file> <sha256>".
sk|win_pointer_format|{name}: o\u010dak\u00e1va sa "<version> <file> <sha256>".
cz|win_pointer_format|{name}: o\u010dek\u00e1v\u00e1 se "<version> <file> <sha256>".

en|win_downgrade|{name} offers {version}, older than the installed {current}. Nothing was changed. To go back on purpose: set PIPSWELL_ALLOW_DOWNGRADE=1
sk|win_downgrade|{name} pon\u00faka {version}, star\u0161iu ne\u017e nain\u0161talovan\u00fa {current}. Ni\u010d sa nezmenilo. Ak sa chce\u0161 vr\u00e1ti\u0165 z\u00e1merne, nastav PIPSWELL_ALLOW_DOWNGRADE=1
cz|win_downgrade|{name} nab\u00edz\u00ed {version}, star\u0161\u00ed ne\u017e nainstalovanou {current}. Nic se nezm\u011bnilo. Pokud se chce\u0161 vr\u00e1tit z\u00e1m\u011brn\u011b, nastav PIPSWELL_ALLOW_DOWNGRADE=1

en|win_native_failed|{what} failed (exit code {code}).
sk|win_native_failed|Krok "{what}" zlyhal (k\u00f3d ukon\u010denia {code}).
cz|win_native_failed|Krok "{what}" selhal (n\u00e1vratov\u00fd k\u00f3d {code}).

en|win_what_python|Installing Python
sk|win_what_python|In\u0161tal\u00e1cia Pythonu
cz|win_what_python|Instalace Pythonu

en|win_not_a_link|{path} is a real folder, not a link; it is not removed. Move it away and run the command again.
sk|win_not_a_link|{path} je skuto\u010dn\u00fd prie\u010dinok, nie odkaz; neodstr\u00e1ni sa. Presu\u0148 ho inam a spusti pr\u00edkaz znova.
cz|win_not_a_link|{path} je skute\u010dn\u00e1 slo\u017eka, ne odkaz; neodstran\u00ed se. P\u0159esu\u0148 ji jinam a spus\u0165 p\u0159\u00edkaz znovu.

en|win_redirected|The download of {url} was redirected to a non-https address.
sk|win_redirected|S\u0165ahovanie {url} bolo presmerovan\u00e9 na adresu bez https.
cz|win_redirected|Stahov\u00e1n\u00ed {url} bylo p\u0159esm\u011brov\u00e1no na adresu bez https.

en|win_acl_unreadable|{dir} has permissions Pipswell cannot read
sk|win_acl_unreadable|{dir} m\u00e1 opr\u00e1vnenia, ktor\u00e9 Pipswell nevie pre\u010d\u00edta\u0165
cz|win_acl_unreadable|{dir} m\u00e1 opr\u00e1vn\u011bn\u00ed, kter\u00e1 Pipswell neum\u00ed p\u0159e\u010d\u00edst

en|win_acl_other_owner|{dir} belongs to another user
sk|win_acl_other_owner|{dir} patr\u00ed in\u00e9mu pou\u017e\u00edvate\u013eovi
cz|win_acl_other_owner|{dir} pat\u0159\u00ed jin\u00e9mu u\u017eivateli

en|win_acl_writable|{dir} can be written by other users ({sid})
sk|win_acl_writable|{dir} m\u00f4\u017eu zapisova\u0165 in\u00ed pou\u017e\u00edvatelia ({sid})
cz|win_acl_writable|{dir} mohou zapisovat jin\u00ed u\u017eivatel\u00e9 ({sid})

en|win_link|{path} is a link (junction or symbolic link)
sk|win_link|{path} je odkaz (junction alebo symbolick\u00fd odkaz)
cz|win_link|{path} je odkaz (junction nebo symbolick\u00fd odkaz)

en|win_foreign_link|{path} is a link Pipswell did not make
sk|win_foreign_link|{path} je odkaz, ktor\u00fd Pipswell nevytvoril
cz|win_foreign_link|{path} je odkaz, kter\u00fd Pipswell nevytvo\u0159il

en|win_link_outside|{path} points outside {dir}
sk|win_link_outside|{path} ukazuje mimo {dir}
cz|win_link_outside|{path} ukazuje mimo {dir}

en|win_refuse|Pipswell will not install code there. Use a folder of your own (PIPSWELL_HOME), or remove the other users' access to it and everything in it first.
sk|win_refuse|Pipswell tam k\u00f3d nenain\u0161taluje. Pou\u017ei vlastn\u00fd prie\u010dinok (PIPSWELL_HOME) alebo najprv odober ostatn\u00fdm pou\u017e\u00edvate\u013eom pr\u00edstup k nemu a ku v\u0161etk\u00e9mu v \u0148om.
cz|win_refuse|Pipswell tam k\u00f3d nenainstaluje. Pou\u017eij vlastn\u00ed slo\u017eku (PIPSWELL_HOME), nebo nejd\u0159\u00edv odeber ostatn\u00edm u\u017eivatel\u016fm p\u0159\u00edstup k n\u00ed a ke v\u0161emu v n\u00ed.

en|win_icacls_code|icacls exited with code {code}
sk|win_icacls_code|icacls skon\u010dil s k\u00f3dom {code}
cz|win_icacls_code|icacls skon\u010dil s k\u00f3dem {code}

en|win_restrict_failed|Could not restrict access to {dir} ({reason}). Nothing was installed.
sk|win_restrict_failed|Nepodarilo sa obmedzi\u0165 pr\u00edstup k {dir} ({reason}). Ni\u010d sa nenain\u0161talovalo.
cz|win_restrict_failed|Nepoda\u0159ilo se omezit p\u0159\u00edstup k {dir} ({reason}). Nic se nenainstalovalo.

en|win_restrict_warn|Warning: could not restrict access to {dir} ({reason}).
sk|win_restrict_warn|Upozornenie: nepodarilo sa obmedzi\u0165 pr\u00edstup k {dir} ({reason}).
cz|win_restrict_warn|Upozorn\u011bn\u00ed: nepoda\u0159ilo se omezit p\u0159\u00edstup k {dir} ({reason}).

en|win_got_content|{dir} got content from someone else while it was being made private. Nothing was installed.
sk|win_got_content|Do {dir} niekto in\u00fd vlo\u017eil obsah po\u010das nastavovania s\u00fakromn\u00e9ho pr\u00edstupu. Ni\u010d sa nenain\u0161talovalo.
cz|win_got_content|Do {dir} n\u011bkdo jin\u00fd vlo\u017eil obsah b\u011bhem nastavov\u00e1n\u00ed soukrom\u00e9ho p\u0159\u00edstupu. Nic se nenainstalovalo.

en|win_private_perms|Could not give {target} the private permissions of {app} (icacls exited with code {code}). Nothing was installed.
sk|win_private_perms|Nepodarilo sa nastavi\u0165 {target} s\u00fakromn\u00e9 opr\u00e1vnenia ako m\u00e1 {app} (icacls skon\u010dil s k\u00f3dom {code}). Ni\u010d sa nenain\u0161talovalo.
cz|win_private_perms|Nepoda\u0159ilo se nastavit {target} soukrom\u00e1 opr\u00e1vn\u011bn\u00ed jako m\u00e1 {app} (icacls skon\u010dil s k\u00f3dem {code}). Nic se nenainstalovalo.

en|win_open_failed|Note: the Pipswell window did not open; run  pipswell open  in a moment.
sk|win_open_failed|Pozn\u00e1mka: okno Pipswell sa neotvorilo; o chv\u00ed\u013eu spusti  pipswell open.
cz|win_open_failed|Pozn\u00e1mka: okno Pipswell se neotev\u0159elo; za chv\u00edli spus\u0165  pipswell open.

en|win_new_terminal|(open a NEW terminal window for the pipswell command to be found)
sk|win_new_terminal|(otvor NOV\u00c9 okno termin\u00e1lu, aby sa na\u0161iel pr\u00edkaz pipswell)
cz|win_new_terminal|(otev\u0159i NOV\u00c9 okno termin\u00e1lu, aby se na\u0161el p\u0159\u00edkaz pipswell)

en|win_uninstall_where|To uninstall: Settings > Apps > Pipswell Desktop, or Settings > Uninstall in Pipswell, or  pipswell uninstall.
sk|win_uninstall_where|Odin\u0161talovanie: Nastavenia > Aplik\u00e1cie > Pipswell Desktop, alebo v Pipswelli Nastavenia > Odin\u0161talova\u0165, alebo  pipswell uninstall.
cz|win_uninstall_where|Odinstalace: Nastaven\u00ed > Aplikace > Pipswell Desktop, nebo v Pipswellu Nastaven\u00ed > Odin\u0161talova\u0165, nebo  pipswell uninstall.

en|win_install_failed|Pipswell install failed: {reason}
sk|win_install_failed|In\u0161tal\u00e1cia Pipswell zlyhala: {reason}
cz|win_install_failed|Instalace Pipswell selhala: {reason}

'@
        $text = $null
        foreach ($l in @($Lang, 'en')) {
            foreach ($line in ($table -split '\r?\n')) {
                if ($line.StartsWith("$l|$Key|", [StringComparison]::Ordinal)) { $text = $line.Substring($l.Length + $Key.Length + 2); break }
            }
            if ($null -ne $text) { break }
        }
        if ($null -eq $text) { return $Key }
        $text = [regex]::Unescape($text)
        $sb = New-Object System.Text.StringBuilder
        $pos = 0
        foreach ($m in [regex]::Matches($text, '\{(\w+)\}')) {
            [void]$sb.Append($text.Substring($pos, $m.Index - $pos))
            $name = $m.Groups[1].Value
            if ($Values -and $Values.ContainsKey($name)) { [void]$sb.Append([string]$Values[$name]) } else { [void]$sb.Append($m.Value) }
            $pos = $m.Index + $m.Length
        }
        [void]$sb.Append($text.Substring($pos))
        return $sb.ToString()
    }
    # ---- messages (end)

    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $uiLang = Get-PipswellLanguage
    function Get-Msg([string]$Key, [hashtable]$Values) { return Get-PipswellMessage $Key $uiLang $Values }
    # the outer catch below asks for its localized "install failed" line this way (nothing else runs)
    if ($PSBoundParameters.ContainsKey('FailureMessage')) { return (Get-Msg 'win_install_failed' @{ reason = $FailureMessage }) }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        # PowerShell 7 already negotiates TLS 1.2 or newer
        $null = $_
    }

    # The releases repo (jarsim/pipswell-desktop-releases). PIPSWELL_RELEASES_URL overrides the address.
    $DEFAULT_RELEASES_URL = 'https://github.com/jarsim/pipswell-desktop-releases/releases/latest/download'
    # the beta channel: its pointers sit in one rolling release (tag beta), each version's zip in its own release
    $DEFAULT_BETA_POINTERS_URL = 'https://github.com/jarsim/pipswell-desktop-releases/releases/download/beta'
    $DEFAULT_TAGS_URL = 'https://github.com/jarsim/pipswell-desktop-releases/releases/download'
    # The owner's offline Ed25519 release key (public half, base64 of the 32 raw bytes); the same value as in
    # pipswell/updater.py and install.sh. While it is the placeholder this installer refuses everything.
    $releaseKey = 'xI0yneFg+9DhXhAOhe05+PSNsp450TsVIAQoK7kLuxk='
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
        if ($LASTEXITCODE -ne 0) { throw (Get-Msg 'win_native_failed' @{ what = $What; code = $LASTEXITCODE }) }
    }

    # Remove a directory JUNCTION without touching what it points to. Never Remove-Item -Recurse on a
    # junction: Windows PowerShell 5.1 can delete the TARGET's contents. Directory.Delete on the link
    # path (not recursive) removes only the link.
    function Remove-Junction([string]$Path) {
        if (-not (Test-Path -LiteralPath $Path)) { return }
        $item = Get-Item -LiteralPath $Path -Force
        if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw (Get-Msg 'win_not_a_link' @{ path = $Path })
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
                throw (Get-Msg 'win_redirected' @{ url = $Url })
            }
        }
    }

    function Get-Sha256([string]$File) {
        return (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    # The numbers pipswell/updater.py version_key compares: the release padded to 4 numbers, then 0 0 for a
    # final release, -1 N for bN and -2 N for .devN (0.2.0.dev28 < 0.2.0b1 < 0.2.0). After - or + : ignored.
    function Get-VersionKey([string]$V) {
        $base = ($V -split '[-+]')[0]
        $m = [regex]::Match($base, '^(\d+(?:\.\d+)*)(?:\.dev(\d+)|b(\d+))?$')
        if (-not $m.Success) {
            return @([regex]::Matches($base, '\d+') | ForEach-Object { [long]$_.Value })
        }
        $key = New-Object System.Collections.Generic.List[long]
        foreach ($d in $m.Groups[1].Value.Split('.')) { $key.Add([long]$d) }
        while ($key.Count -lt 4) { $key.Add(0) }
        if ($m.Groups[2].Success) { $key.Add(-2); $key.Add([long]$m.Groups[2].Value) }
        elseif ($m.Groups[3].Success) { $key.Add(-1); $key.Add([long]$m.Groups[3].Value) }
        else { $key.Add(0); $key.Add(0) }
        return @($key.ToArray())
    }

    # Why the release key may not be used ('' = fine): the placeholder in a build the owner has not switched on, or
    # something that is not 43 base64 characters and "=". Nothing is checked or installed without a key.
    function Get-ReleaseKeyProblem([string]$Key) {
        if ($Key -clike 'REPLACE-WITH-*') {
            return (Get-Msg 'key_none')
        }
        if ($Key -cnotmatch '^[A-Za-z0-9+/]{43}=$') {
            return (Get-Msg 'key_bad')
        }
        return ''
    }

    # Throws unless the release list $Pointer is signed ($Sig, base64) by the release key $Key FOR THIS NAME (the
    # signature covers the file's name, so a beta list renamed to the stable name fails). Runs the managed
    # Python directly (uv python find, not uv run: nothing is created in the uv cache) with -B -I: no bytecode, no
    # user site, nothing imported from the current folder. Mirrors pipswell/updater.py verify_pointer.
    function Confirm-PointerSignature([string]$Pointer, [string]$Sig, [string]$Key, [string]$Work) {
        $found = @(& $uv python find --managed-python --no-project $PYTHON_VERSION)
        if ($LASTEXITCODE -ne 0 -or $found.Count -lt 1) { throw (Get-Msg 'no_python') }
        $exe = ([string]$found[0]).Trim()
        # uv also looks in virtual environments (an active one, a .venv in the current folder): only a Python inside
        # the app folder (private, checked before) may run here
        $sep = [string][IO.Path]::DirectorySeparatorChar
        $inApp = ([IO.Path]::GetFullPath($exe)).StartsWith(([IO.Path]::GetFullPath($appRoot).TrimEnd($sep) + $sep), [StringComparison]::OrdinalIgnoreCase)
        if (-not $inApp) { throw (Get-Msg 'python_foreign' @{ python = $exe }) }
        $script = Join-Path $Work 'verify_pointer.py'
        $code = @'
import base64, hashlib, sys

# Ed25519 verification (RFC 8032), standard library only: it runs with the Python the installer just installed,
# before anything from a release is used. Arguments: <public key, base64> <pointer file> <signature file, base64> <pointer name>.
P = 2**255 - 19
L = 2**252 + 27742317777372353535851937790883648493
D = -121665 * pow(121666, P - 2, P) % P
SQRT_M1 = pow(2, (P - 1) // 4, P)


def decompress(b):
    n = int.from_bytes(b, "little")
    sign, y = n >> 255, n & ((1 << 255) - 1)
    if y >= P:
        return None
    x2 = (y * y - 1) * pow(D * y * y + 1, P - 2, P) % P
    if x2 == 0:
        return None if sign else (0, y, 1, 0)
    x = pow(x2, (P + 3) // 8, P)
    if (x * x - x2) % P:
        x = x * SQRT_M1 % P
    if (x * x - x2) % P:
        return None
    if x & 1 != sign:
        x = P - x
    return (x, y, 1, x * y % P)


def add(p, q):
    a = (p[1] - p[0]) * (q[1] - q[0]) % P
    b = (p[1] + p[0]) * (q[1] + q[0]) % P
    c = 2 * p[3] * q[3] * D % P
    d = 2 * p[2] * q[2] % P
    e, f, g, h = b - a, d - c, d + c, b + a
    return (e * f % P, g * h % P, f * g % P, e * h % P)


def mul(s, p):
    q = (0, 1, 1, 0)
    while s:
        if s & 1:
            q = add(q, p)
        p = add(p, p)
        s >>= 1
    return q


BASE = decompress((4 * pow(5, P - 2, P) % P).to_bytes(32, "little"))


def verify(pub, msg, sig):
    if len(pub) != 32 or len(sig) != 64:
        return False
    a, r = decompress(pub), decompress(sig[:32])
    s = int.from_bytes(sig[32:], "little")
    if a is None or r is None or s >= L:
        return False
    h = int.from_bytes(hashlib.sha512(sig[:32] + pub + msg).digest(), "little") % L
    x1, y1, z1, _ = mul(s, BASE)
    x2, y2, z2, _ = add(r, mul(h, a))
    return (x1 * z2 - x2 * z1) % P == 0 and (y1 * z2 - y2 * z1) % P == 0


def main(argv):
    if len(argv) != 4:
        sys.exit("usage: verify_pointer.py <public key> <pointer file> <signature file> <pointer name>")
    try:
        pub = base64.b64decode(argv[0], validate=True)
        with open(argv[1], "rb") as f:
            data = f.read(4097)
        with open(argv[2], "rb") as f:
            sig = base64.b64decode(f.read(1025).strip(), validate=True)
        name = argv[3].encode("ascii")
    except (OSError, ValueError) as e:
        sys.exit(f"cannot read the key, the release list or its signature: {e}")
    if len(data) > 4096:
        sys.exit("the release list is too large")
    # the signed message names the pointer (channel and platform): pipswell/updater.py pointer_message
    if not verify(pub, b"pipswell-release-pointer-v1\0" + name + b"\0" + data, sig):
        sys.exit("the signature of the release list is not valid")


if __name__ == "__main__":
    main(sys.argv[1:])
'@
        [IO.File]::WriteAllText($script, $code, (New-Object Text.UTF8Encoding($false)))
        & $exe -B -I $script $Key $Pointer $Sig (Split-Path -Leaf $Pointer)
        if ($LASTEXITCODE -ne 0) {
            throw (Get-Msg 'sig_invalid' @{ name = (Split-Path -Leaf $Pointer) })
        }
    }

    # Fetch the release list $Name and $Name.sig into $work, verify the signature, then return the list's first line.
    # Nothing of an unsigned or wrongly signed list is read.
    function Read-SignedPointer([string]$Name) {
        $file = Join-Path $work $Name
        try { Get-Download "$releasesUrl/$Name" $file $loopbackHttp } catch { throw (Get-Msg 'pointer_unreadable' @{ url = "$releasesUrl/$Name" }) }
        try {
            Get-Download "$releasesUrl/$Name.sig" "$file.sig" $loopbackHttp
        } catch {
            throw (Get-Msg 'pointer_no_sig' @{ name = $Name; url = "$releasesUrl/$Name" })
        }
        Confirm-PointerSignature $file "$file.sig" $releaseKey $work
        return [string](Get-Content -LiteralPath $file -TotalCount 1)
    }

    # The release channel: PIPSWELL_CHANNEL ($Value), else the one a previous install stored in app\channel ($StoredFile,
    # so re-running the installer keeps a beta install on beta), else stable; anything else throws (a typo must not
    # silently pick another channel). Mirrors pipswell/updater.py channel / stored_channel.
    function Get-Channel([string]$Value, [string]$StoredFile) {
        if (-not $Value -and $StoredFile -and (Test-Path -LiteralPath $StoredFile -PathType Leaf)) {
            $item = Get-Item -LiteralPath $StoredFile -Force
            if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $Value = "$(Get-Content -LiteralPath $StoredFile -TotalCount 1)".Trim()
                if ($Value.Length -gt 64) { $Value = $Value.Substring(0, 64) }
                if ($Value -and $Value -cne 'stable' -and $Value -cne 'beta') { throw (Get-Msg 'channel_stored_bad' @{ file = $StoredFile; value = $Value }) }
            }
        }
        if (-not $Value) { return 'stable' }
        if ($Value -cne 'stable' -and $Value -cne 'beta') { throw (Get-Msg 'channel_env_bad' @{ value = $Value }) }
        return $Value
    }

    # Where the channel's release lists are: PIPSWELL_RELEASES_URL ($Override) or the built-in address.
    function Get-ReleasesUrl([string]$Channel, [string]$Override) {
        if ($Override) { return $Override }
        if ($Channel -ceq 'beta') { return $DEFAULT_BETA_POINTERS_URL }
        return $DEFAULT_RELEASES_URL
    }

    # The release list of a platform build: the beta channel's has beta- in it.
    function Get-PointerName([string]$Channel, [string]$Platform) {
        if ($Channel -ceq 'beta') { return "latest-beta-$Platform.txt" }
        return "latest-$Platform.txt"
    }

    # Where the zip and its .sha256 are: with the lists (PIPSWELL_RELEASES_URL set, or stable), else for a beta in
    # that version's own release (the version has passed the shape check, so it adds no path or query).
    function Get-AssetBase([string]$Version) {
        if ($env:PIPSWELL_RELEASES_URL -or $channel -cne 'beta') { return $releasesUrl }
        return "$DEFAULT_TAGS_URL/v$Version"
    }

    # Whether version A is older than B (compared number by number; a shorter equal prefix is older)
    function Test-VersionOlder([string]$A, [string]$B) {
        $x = @(Get-VersionKey $A); $y = @(Get-VersionKey $B)
        for ($i = 0; $i -lt [Math]::Min($x.Count, $y.Count); $i++) {
            if ($x[$i] -lt $y[$i]) { return $true }
            if ($x[$i] -gt $y[$i]) { return $false }
        }
        return ($x.Count -lt $y.Count)
    }

    # Whether app\<Version> may be used as it is: its .installed holds the SHA256 verified for this release, or it
    # is the one already running with its .venv (switching to it activates nothing new; folders made by older
    # updaters carry no .installed). A bare .installed no longer skips the download (pentest M2). The stamp ties a
    # folder to its release; it is no defence against someone who can write app\ (the hash is public).
    # Either way it needs its .venv (as pipswell/updater.py unpack): a stamped folder without one is unpacked again.
    function Test-Reusable([string]$Dir, [string]$Sha, [string]$Version, [string]$Current) {
        if (-not (Test-Path -LiteralPath (Join-Path $Dir '.venv') -PathType Container)) { return $false }
        $stampFile = Join-Path $Dir '.installed'
        if (Test-Path -LiteralPath $stampFile -PathType Leaf) {
            $stamp = ([string](Get-Content -LiteralPath $stampFile -TotalCount 1)).Trim()
            if ($stamp -ceq $Sha) { return $true }
        }
        return ([bool]$Current -and ($Version -ceq $Current))
    }

    # The owner and access rules of a folder, one per line (the same lines pipswell/updater.py ACL_READER prints):
    # "U <this user's SID>", "O <owner SID>", "A <0 allow / 1 deny> <rights mask> <SID>".
    function Get-FolderAcl([string]$p) {
        $acl = Get-Acl -LiteralPath $p
        'U ' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        'O ' + $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
        foreach ($r in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            'A ' + [int]$r.AccessControlType + ' ' + [int64]$r.FileSystemRights + ' ' + $r.IdentityReference.Value
        }
    }
    # Why a folder may not hold code this user runs ('' = fine), from Get-FolderAcl's lines: it must be owned by this
    # user, SYSTEM or Administrators, and nobody else may be allowed to write, add, delete or re-permission anything in
    # it. A shared folder another user can write would let them plant app\<ver>\.venv plus a .installed holding the
    # public SHA256, or app\bin\uv.exe (security review 2026-11-15). Mirrors pipswell/updater.py acl_problem.
    function Get-AclProblem([string]$Dir, [string[]]$Lines) {
        # WriteData/AddFile, AppendData/AddSubdirectory, WriteExtendedAttributes, DeleteSubdirectoriesAndFiles,
        # WriteAttributes, Delete, ChangePermissions, TakeOwnership, GENERIC_ALL, GENERIC_WRITE
        $writeMask = [int64]0x500D0156
        $user = ''; $owner = ''; $aces = @()
        foreach ($line in $Lines) {
            $f = ([string]$line).Trim() -split '\s+'
            if ($f[0] -ceq 'U' -and $f.Count -eq 2) { $user = $f[1] }
            elseif ($f[0] -ceq 'O' -and $f.Count -eq 2) { $owner = $f[1] }
            elseif ($f[0] -ceq 'A' -and $f.Count -eq 4) { $aces += , $f }
            elseif ($f[0]) { return (Get-Msg 'win_acl_unreadable' @{ dir = $Dir }) }
        }
        if (-not $user -or -not $owner) { return (Get-Msg 'win_acl_unreadable' @{ dir = $Dir }) }
        $trusted = @($user, 'S-1-5-18', 'S-1-5-32-544')
        if ($trusted -notcontains $owner) { return (Get-Msg 'win_acl_other_owner' @{ dir = $Dir }) }
        $trusted += @('S-1-3-0', 'S-1-3-4')        # CREATOR OWNER, OWNER RIGHTS: the owner checked above
        foreach ($a in $aces) {
            $mask = [int64]0
            if (-not [int64]::TryParse($a[2], [ref]$mask)) { return (Get-Msg 'win_acl_unreadable' @{ dir = $Dir }) }
            if ($a[1] -ceq '0' -and ($mask -band $writeMask) -and ($trusted -notcontains $a[3])) {
                return (Get-Msg 'win_acl_writable' @{ dir = $Dir; sid = $a[3] })
            }
        }
        return ''
    }

    # Why the install may not trust what is in the home folder ('' = fine). Checked: the home folder, app\, everything
    # directly in app\ (bin, python, uv-cache, each version folder) and app\bin\uv.exe. A link there could be pointed
    # elsewhere after the check, so home and app\ may not be one, and in app\ only the current / .current.new
    # junctions this installer makes are allowed (current pointing into app\). Mirrors pipswell/updater.py
    # trust_problem. Deeper files are not walked (a full walk of .venv and uv-cache would take minutes).
    function Get-TrustProblem([string]$HomeDir, [string]$AppRoot, [string]$Uv) {
        $paths = @($HomeDir, $AppRoot)
        foreach ($p in $paths) {
            if ((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                return (Get-Msg 'win_link' @{ path = $p })
            }
        }
        if (Test-Path -LiteralPath $AppRoot) {
            $appFull = [IO.Path]::GetFullPath($AppRoot).TrimEnd('\')
            foreach ($item in @(Get-ChildItem -LiteralPath $AppRoot -Force)) {
                if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $paths += $item.FullName; continue }
                if (@('current', '.current.new') -notcontains $item.Name) { return (Get-Msg 'win_foreign_link' @{ path = $item.FullName }) }
                $target = [string](@($item.Target)[0])
                if (-not $target -or ([IO.Path]::GetFullPath((Split-Path -Parent $target)).TrimEnd('\') -ne $appFull)) {
                    return (Get-Msg 'win_link_outside' @{ path = $item.FullName; dir = $AppRoot })
                }
            }
            if (Test-Path -LiteralPath $Uv) { $paths += $Uv }
        }
        foreach ($p in $paths) {
            if (-not (Test-Path -LiteralPath $p)) { continue }
            $problem = Get-AclProblem $p @(Get-FolderAcl $p)
            if ($problem) { return $problem }
        }
        return ''
    }

    # ---- this machine ---------------------------------------------------------------------------
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw (Get-Msg 'win_not_windows') }
    if ([Environment]::OSVersion.Version.Major -lt 10) { throw (Get-Msg 'win_old_windows') }
    if (-not [Environment]::Is64BitOperatingSystem) { throw (Get-Msg 'win_not_64bit') }
    $arch = $env:PROCESSOR_ARCHITEW6432
    if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
    if ($arch -eq 'ARM64') {
        Say (Get-Msg 'win_arm_note')
    }

    $homeDir = $env:PIPSWELL_HOME
    $customHome = [bool]$homeDir
    if (-not $homeDir) {
        if (-not $env:LOCALAPPDATA) { throw (Get-Msg 'win_no_localappdata') }
        $homeDir = Join-Path $env:LOCALAPPDATA 'Pipswell'
    }
    $appRoot = Join-Path $homeDir 'app'
    $binDir = Join-Path $appRoot 'bin'
    $uv = Join-Path $binDir 'uv.exe'
    $cli = Join-Path $binDir 'pipswell.cmd'
    $channelFile = Join-Path $appRoot 'channel'
    $channel = Get-Channel $env:PIPSWELL_CHANNEL $channelFile
    $releasesUrl = (Get-ReleasesUrl $channel $env:PIPSWELL_RELEASES_URL).TrimEnd('/')
    if ($releasesUrl -like '*<OWNER>*') {
        throw (Get-Msg 'win_owner_placeholder')
    }
    # Parsed, not prefix-matched: https://host/... without credentials, or plain http for the exact host
    # 127.0.0.1 only (a local test server). http://127.0.0.1.evil.example begins like an allowed address.
    $urlMatch = [regex]::Match($releasesUrl, '^(https|http)://([^/?#@\s]+)(/\S*)?$')
    if (-not $urlMatch.Success) { throw (Get-Msg 'url_not_https_creds') }
    $urlScheme = $urlMatch.Groups[1].Value
    $urlHost = ($urlMatch.Groups[2].Value -split ':')[0]
    $loopbackHttp = $false
    if ($urlScheme -eq 'http') {
        if ($urlHost -ne '127.0.0.1') { throw (Get-Msg 'url_not_https') }
        $loopbackHttp = $true
    }
    # no signing key, no install: refused before anything is written
    $keyProblem = Get-ReleaseKeyProblem $releaseKey
    if ($keyProblem) { throw $keyProblem }


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
        throw (Get-Msg 'win_mt5_missing' @{ setup = $MT5_SETUP; page = $MT5_PAGE })
    }
    Say (Get-Msg 'win_mt5_found' @{ path = $mt5 })

    # The folder holds the code the jobs run and the secrets (ADMIN_TOKEN, BRIDGE_SECRET, ledgers). One that already
    # exists must be this user's and writable by nobody else (another user could have planted code in it). Then it
    # is made private (this user, SYSTEM and Administrators only, inheritance removed) BEFORE anything goes in, and
    # checked again: a new folder that was not made private, or that got content meanwhile, stops the install.
    $refuse = Get-Msg 'win_refuse'
    # Windows PowerShell started from a PowerShell 7 terminal inherits pwsh's PSModulePath and would autoload Get-Acl's
    # module from PowerShell 7 (which it cannot run): load its own (pipswell/updater.py ACL_READER does the same).
    if ($PSVersionTable.PSVersion.Major -lt 6) { Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security') }
    $icacls = Join-Path $env:SystemRoot 'System32\icacls.exe'
    $homeExisted = Test-Path -LiteralPath $homeDir
    $problem = Get-TrustProblem $homeDir $appRoot $uv
    if ($problem) { throw "$problem. $refuse" }
    New-Item -ItemType Directory -Force -Path $homeDir | Out-Null
    try {
        $userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        & $icacls $homeDir /inheritance:r /grant:r "*${userSid}:(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw (Get-Msg 'win_icacls_code' @{ code = $LASTEXITCODE }) }
    } catch {
        if ($homeExisted) { throw (Get-Msg 'win_restrict_failed' @{ dir = $homeDir; reason = $_.Exception.Message }) }
        Say (Get-Msg 'win_restrict_warn' @{ dir = $homeDir; reason = $_.Exception.Message })
    }
    if (-not $homeExisted -and @(Get-ChildItem -LiteralPath $homeDir -Force).Count -gt 0) {
        throw (Get-Msg 'win_got_content' @{ dir = $homeDir })
    }
    $problem = Get-TrustProblem $homeDir $appRoot $uv
    if ($problem) { throw "$problem. $refuse" }
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    # uv keeps Python, its cache and any Python links in the app folder: nothing to clean up elsewhere.
    $env:UV_PYTHON_INSTALL_DIR = Join-Path $appRoot 'python'
    $env:UV_CACHE_DIR = Join-Path $appRoot 'uv-cache'
    $env:UV_PYTHON_BIN_DIR = $binDir
    $env:UV_NO_MODIFY_PATH = '1'
    # no uv.toml (the current folder's, the user's) may redirect the package index or the Python download
    $env:UV_NO_CONFIG = '1'

    $work = Join-Path ([IO.Path]::GetTempPath()) ('pipswell-install-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    try {
        # ---- uv, into the app folder only ---------------------------------------------------------
        if (-not (Test-Path -LiteralPath $uv -PathType Leaf)) {
            Say (Get-Msg 'installing_uv' @{ version = $UV_VERSION; dir = $binDir })
            $uvZip = Join-Path $work 'uv.zip'
            Get-Download "https://github.com/astral-sh/uv/releases/download/$UV_VERSION/uv-x86_64-pc-windows-msvc.zip" $uvZip $false
            if ((Get-Sha256 $uvZip) -ne $UV_WIN_SHA256) { throw (Get-Msg 'win_uv_sha') }
            $uvOut = Join-Path $work 'uv-x'
            Expand-Archive -LiteralPath $uvZip -DestinationPath $uvOut -Force
            $found = Get-ChildItem -LiteralPath $uvOut -Recurse -Filter 'uv.exe' | Select-Object -First 1
            if (-not $found) { throw (Get-Msg 'win_uv_exe_missing') }
            foreach ($name in 'uv.exe', 'uvx.exe') {
                $src = Join-Path $found.DirectoryName $name
                if (Test-Path -LiteralPath $src -PathType Leaf) { Copy-Item -LiteralPath $src -Destination $binDir -Force }
            }
            if (-not (Test-Path -LiteralPath $uv -PathType Leaf)) { throw (Get-Msg 'uv_not_installed' @{ dir = $binDir }) }
        }
        Say (Get-Msg 'python_step' @{ version = $PYTHON_VERSION })
        Invoke-Native $uv @('python', 'install', $PYTHON_VERSION) (Get-Msg 'win_what_python')

        # ---- the release: version, file and hash come from the SIGNED latest-windows-x64.txt (the compiled
        # Windows build); the zip must match them -----
        Say (Get-Msg 'looking_release' @{ channel = $channel })
        $platform = 'windows-x64'
        $latestName = Get-PointerName $channel $platform
        $line = Read-SignedPointer $latestName
        $parts = @(([string]$line).Trim() -split '\s+')
        if ($parts.Count -lt 3) { throw (Get-Msg 'win_pointer_format' @{ name = $latestName }) }
        $version = $parts[0]; $file = $parts[1]; $sha = $parts[2]
        if ($version -notmatch '^[0-9]+(\.[0-9]+){1,3}([-+.][0-9A-Za-z.]+|b[0-9]+)?$') { throw (Get-Msg 'bad_version' @{ name = $latestName }) }
        if ($file -cne "pipswell-desktop-$version-$platform.zip") { throw (Get-Msg 'bad_file' @{ name = $latestName }) }
        if ($sha -cnotmatch '^[0-9a-f]{64}$') { throw (Get-Msg 'bad_sha' @{ name = $latestName }) }

        # The stable channel never takes a beta (bN) or dev (.devN) build: a pointer from another channel is no stable
        # release. The one exception is a dev build of the 0.2.0 line (the dev28 transition; pipswell/updater.py
        # check_channel_version, tools/build_release.py DEV_ON_STABLE_LINE).
        $stableBase = ($version -split '[-+]')[0]
        if ($channel -ceq 'stable' -and $stableBase -cmatch '^[0-9]+(\.[0-9]+)*(\.dev[0-9]+|b[0-9]+)$' -and $stableBase -cnotmatch '^0\.2\.0\.dev[0-9]+$') {
            throw (Get-Msg 'stable_refuses' @{ name = $latestName; version = $version })
        }

        $currentVersion = ''
        $currentLink = Join-Path $appRoot 'current'
        if (Test-Path -LiteralPath $currentLink) {
            $linkItem = Get-Item -LiteralPath $currentLink -Force
            if (($linkItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $linkItem.Target) {
                $currentVersion = Split-Path -Leaf ([string]@($linkItem.Target)[0])
            }
        }
        # A replayed or older release pointer must not move an install back onto an older (maybe vulnerable) build.
        if ($currentVersion -and (Test-VersionOlder $version $currentVersion) -and $env:PIPSWELL_ALLOW_DOWNGRADE -ne '1') {
            throw (Get-Msg 'win_downgrade' @{ name = $latestName; version = $version; current = $currentVersion })
        }

        $target = Join-Path $appRoot $version
        if (Test-Reusable $target $sha $version $currentVersion) {
            Say (Get-Msg 'already_unpacked' @{ version = $version })
        } else {
            Say (Get-Msg 'downloading' @{ version = $version })
            $zip = Join-Path $work $file
            $side = Join-Path $work "$file.sha256"
            $assets = Get-AssetBase $version
            Get-Download "$assets/$file" $zip $loopbackHttp
            Get-Download "$assets/$file.sha256" $side $loopbackHttp
            $got = Get-Sha256 $zip
            $sideSha = (([string](Get-Content -LiteralPath $side -TotalCount 1)).Trim() -split '\s+')[0].ToLowerInvariant()
            if ($got -ne $sha) { throw (Get-Msg 'sha_mismatch' @{ name = $latestName }) }
            if ($sideSha -ne $sha) { throw (Get-Msg 'sha_side' @{ file = $file; name = $latestName }) }
            Say (Get-Msg 'sha_verified')

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
                throw (Get-Msg 'zip_unsafe')
            }
            $top = Join-Path $unpacked "pipswell-desktop-$version"
            if (-not (Test-Path -LiteralPath $top -PathType Container)) { throw (Get-Msg 'layout_bad') }
            if (Test-Path -LiteralPath $target) {
                $existing = Get-Item -LiteralPath $target -Force
                if ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    [IO.Directory]::Delete($target)
                } else {
                    Remove-Item -LiteralPath $target -Recurse -Force
                }
            }
            Move-Item -LiteralPath $top -Destination $target
            # A move keeps the permissions it had in %TEMP% (a TEMP outside the profile, e.g. C:\Temp, lets other
            # users write it): give it app\'s private ones before anything in it runs.
            & $icacls $target /reset /T /Q | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
                throw (Get-Msg 'win_private_perms' @{ target = $target; app = $appRoot; code = $LASTEXITCODE })
            }
            Say (Get-Msg 'installing_packages')
            try {
                Invoke-Native $uv @('sync', '--frozen', '--no-dev', '--python', $PYTHON_VERSION, '--project', $target) 'uv sync'
            } catch {
                Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
                throw (Get-Msg 'sync_failed')
            }
            Set-Content -LiteralPath (Join-Path $target '.installed') -Value $sha -Encoding ascii
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

        # Remember the channel: `pipswell update` and the portal's update check read app\channel when PIPSWELL_CHANNEL
        # is not set (pipswell/updater.py channel). One ASCII line (LF), written beside the other files of app\.
        [IO.File]::WriteAllText("$channelFile.new", "$channel`n", (New-Object Text.ASCIIEncoding))
        Move-Item -LiteralPath "$channelFile.new" -Destination $channelFile -Force

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
        if ($LASTEXITCODE -ne 0) { Say (Get-Msg 'win_open_failed') }
        Say ''
        Say (Get-Msg 'running' @{ version = $version })
        Say '  pipswell status    pipswell doctor    pipswell stop    pipswell update    pipswell uninstall'
        Say ('  ' + (Get-Msg 'win_new_terminal'))
        Say (Get-Msg 'win_uninstall_where')
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

try {
    Install-Pipswell
} catch {
    Write-Host ''
    $reason = $_.Exception.Message
    $failure = 'Pipswell install failed: ' + $reason
    try { $failure = [string](Install-Pipswell -FailureMessage $reason) } catch { $null = $_ }
    Write-Host $failure -ForegroundColor Red
    $global:LASTEXITCODE = 1
}
