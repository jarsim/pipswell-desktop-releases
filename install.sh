#!/bin/bash
#
# Pipswell Desktop installer (macOS):
#
#     curl -fsSL <releases address>/install.sh | bash
#
# Idempotent: running it again IS the update (same steps, newest release, jobs restarted).
# Nothing outside ~/Library/Application Support/Pipswell, ~/Applications/Pipswell.app and
# ~/.local/bin/pipswell is touched; no shell profile is edited; no sudo.
#
#   PIPSWELL_RELEASES_URL   where latest-<platform>.txt, its .sig, the zip and its .sha256 live
#                           (default: the placeholder below; set the real address, see installer/README.md)
#   PIPSWELL_CHANNEL        beta: the newest beta (vX.Y.ZbN, vX.Y.Z.devN); unset or stable: stable releases only
#
# The release list (latest-<platform>.txt) is used only after its Ed25519 signature (<file>.sig, made offline by the
# owner) verifies against RELEASE_PUBLIC_KEY below. macOS /usr/bin/openssl is LibreSSL 3.3.6 and cannot verify
# Ed25519, so the check runs in the Python this installer installs (stdlib only), before anything of the release is used.
#   PIPSWELL_HOME           install somewhere else than ~/Library/Application Support/Pipswell
#   PIPSWELL_LANG           sk, cz or en: the language of the messages (default: the Mac's language: Slovak, Czech, else English)
set -euo pipefail
# Nothing this script makes (app/bin, the version folder, Python, the uv cache) may be writable by others: the next
# run and `pipswell update` refuse such folders (app_entries_ok), so a shell with umask 002 must not leave them so.
umask 022

# ---- messages (begin): every line the user reads. One table, the same keys and texts as install.ps1 (tests/test_installer_lang.py
# compares them). `lang|key|text`: lang en, sk or cz; \n is a line break; {name} is filled by msg. Keys with mac_ exist only here.
read -r -d '' MSG_TABLE <<'MSGS' || true
en|channel_stored_bad|{file} must say stable or beta, not {value}
sk|channel_stored_bad|{file} musí obsahovať stable alebo beta, nie {value}
cz|channel_stored_bad|{file} musí obsahovat stable nebo beta, ne {value}

en|channel_env_bad|PIPSWELL_CHANNEL must be stable or beta, not {value}
sk|channel_env_bad|PIPSWELL_CHANNEL musí byť stable alebo beta, nie {value}
cz|channel_env_bad|PIPSWELL_CHANNEL musí být stable nebo beta, ne {value}

en|url_not_https_creds|PIPSWELL_RELEASES_URL must be an https:// address (no credentials).
sk|url_not_https_creds|PIPSWELL_RELEASES_URL musí byť adresa https:// (bez prihlasovacích údajov).
cz|url_not_https_creds|PIPSWELL_RELEASES_URL musí být adresa https:// (bez přihlašovacích údajů).

en|url_not_https|PIPSWELL_RELEASES_URL must be an https:// address.
sk|url_not_https|PIPSWELL_RELEASES_URL musí byť adresa https://.
cz|url_not_https|PIPSWELL_RELEASES_URL musí být adresa https://.

en|key_none|This installer carries no release signing key yet, so it cannot verify a release. Nothing was installed or changed.
sk|key_none|Tento inštalátor zatiaľ nemá podpisový kľúč vydaní, takže nemôže overiť vydanie. Nič sa nenainštalovalo ani nezmenilo.
cz|key_none|Tento instalátor zatím nemá podpisový klíč vydání, takže nemůže ověřit vydání. Nic se nenainstalovalo ani nezměnilo.

en|key_bad|The release signing key in this installer is malformed. Nothing was installed or changed.
sk|key_bad|Podpisový kľúč vydaní v tomto inštalátore je poškodený. Nič sa nenainštalovalo ani nezmenilo.
cz|key_bad|Podpisový klíč vydání v tomto instalátoru je poškozený. Nic se nenainstalovalo ani nezměnilo.

en|no_python|No Python found to verify the release signature. Nothing was installed.
sk|no_python|Nenašiel sa Python na overenie podpisu vydania. Nič sa nenainštalovalo.
cz|no_python|Nenašel se Python pro ověření podpisu vydání. Nic se nenainstalovalo.

en|python_foreign|The Python found for the signature check ({python}) is not the one this installer installed. Nothing was installed.
sk|python_foreign|Python nájdený na overenie podpisu ({python}) nie je ten, ktorý nainštaloval tento inštalátor. Nič sa nenainštalovalo.
cz|python_foreign|Python nalezený pro ověření podpisu ({python}) není ten, který nainstaloval tento instalátor. Nic se nenainstalovalo.

en|sig_invalid|{name} is not signed by the Pipswell release key. Nothing was installed or changed.
sk|sig_invalid|{name} nie je podpísaný vydavateľským kľúčom Pipswell. Nič sa nenainštalovalo ani nezmenilo.
cz|sig_invalid|{name} není podepsaný vydavatelským klíčem Pipswell. Nic se nenainstalovalo ani nezměnilo.

en|pointer_unreadable|Could not read {url}
sk|pointer_unreadable|Nepodarilo sa prečítať {url}
cz|pointer_unreadable|Nepodařilo se přečíst {url}

en|pointer_no_sig|{name} has no signature ({url}.sig could not be read): this release is not signed. Nothing was installed or changed.
sk|pointer_no_sig|{name} nemá podpis ({url}.sig sa nepodarilo prečítať): toto vydanie nie je podpísané. Nič sa nenainštalovalo ani nezmenilo.
cz|pointer_no_sig|{name} nemá podpis ({url}.sig se nepodařilo přečíst): toto vydání není podepsané. Nic se nenainstalovalo ani nezměnilo.

en|installing_uv|Installing uv {version} into {dir} ...
sk|installing_uv|Inštalujem uv {version} do {dir} ...
cz|installing_uv|Instaluji uv {version} do {dir} ...

en|uv_not_installed|uv did not install into {dir}.
sk|uv_not_installed|uv sa nenainštaloval do {dir}.
cz|uv_not_installed|uv se nenainstaloval do {dir}.

en|python_step|Python {version} ...
sk|python_step|Python {version} ...
cz|python_step|Python {version} ...

en|looking_release|Looking for the newest release ({channel}) ...
sk|looking_release|Hľadám najnovšie vydanie ({channel}) ...
cz|looking_release|Hledám nejnovější vydání ({channel}) ...

en|bad_version|{name}: bad version.
sk|bad_version|{name}: neplatná verzia.
cz|bad_version|{name}: neplatná verze.

en|bad_file|{name}: bad file name.
sk|bad_file|{name}: neplatný názov súboru.
cz|bad_file|{name}: neplatný název souboru.

en|bad_sha|{name}: bad SHA256.
sk|bad_sha|{name}: neplatný SHA256.
cz|bad_sha|{name}: neplatný SHA256.

en|stable_refuses|{name} offers {version}, a beta or dev build: the stable channel does not take it. Nothing was installed or changed.
sk|stable_refuses|{name} ponúka {version}, čo je beta alebo vývojová zostava: stabilný kanál ju neprijíma. Nič sa nenainštalovalo ani nezmenilo.
cz|stable_refuses|{name} nabízí {version}, což je beta nebo vývojové sestavení: stabilní kanál ho nepřijímá. Nic se nenainstalovalo ani nezměnilo.

en|already_unpacked|Pipswell {version} is already unpacked.
sk|already_unpacked|Pipswell {version} je už rozbalený.
cz|already_unpacked|Pipswell {version} je už rozbalený.

en|downloading|Downloading Pipswell {version} ...
sk|downloading|Sťahujem Pipswell {version} ...
cz|downloading|Stahuji Pipswell {version} ...

en|sha_mismatch|The download does not match the SHA256 in {name}. Nothing was installed.
sk|sha_mismatch|Stiahnutý súbor nezodpovedá SHA256 v {name}. Nič sa nenainštalovalo.
cz|sha_mismatch|Stažený soubor neodpovídá SHA256 v {name}. Nic se nenainstalovalo.

en|sha_side|{file}.sha256 disagrees with {name}. Nothing was installed.
sk|sha_side|{file}.sha256 sa nezhoduje s {name}. Nič sa nenainštalovalo.
cz|sha_side|{file}.sha256 se neshoduje s {name}. Nic se nenainstalovalo.

en|sha_verified|SHA256 verified.
sk|sha_verified|SHA256 overený.
cz|sha_verified|SHA256 ověřen.

en|zip_unsafe|The release zip failed the safety checks. Nothing was installed.
sk|zip_unsafe|Archív vydania neprešiel bezpečnostnými kontrolami. Nič sa nenainštalovalo.
cz|zip_unsafe|Archiv vydání neprošel bezpečnostními kontrolami. Nic se nenainstalovalo.

en|layout_bad|Unexpected release layout.
sk|layout_bad|Neočakávaná štruktúra vydania.
cz|layout_bad|Neočekávaná struktura vydání.

en|installing_packages|Installing the Python packages (locked versions) ...
sk|installing_packages|Inštalujem balíky Pythonu (zamknuté verzie) ...
cz|installing_packages|Instaluji balíčky Pythonu (zamčené verze) ...

en|sync_failed|uv sync failed; the previous version (if any) is untouched.
sk|sync_failed|uv sync zlyhal; predchádzajúca verzia (ak nejaká je) zostala nedotknutá.
cz|sync_failed|uv sync selhal; předchozí verze (pokud nějaká je) zůstala nedotčená.

en|running|Pipswell {version} is running. Everything is DRY: nothing real is placed until you switch it off yourself.
sk|running|Pipswell {version} beží. Všetko je v testovacom režime (DRY): nič sa naozaj neotvorí, kým ho sám nevypneš.
cz|running|Pipswell {version} běží. Všechno je v testovacím režimu (DRY): nic se doopravdy neotevře, dokud ho sám nevypneš.
en|mac_uninstall_where|To uninstall: Settings > Uninstall in Pipswell, or  pipswell uninstall. Moving Pipswell.app to the Trash does not stop Pipswell.
sk|mac_uninstall_where|Odinštalovanie: v Pipswelli Nastavenia > Odinštalovať, alebo  pipswell uninstall. Presunutie Pipswell.app do koša Pipswell nezastaví.
cz|mac_uninstall_where|Odinstalace: v Pipswellu Nastavení > Odinštalovať, nebo  pipswell uninstall. Přesunutí Pipswell.app do koše Pipswell nezastaví.

en|mac_not_macos|Pipswell Desktop supports macOS in this release (Windows and Linux come later).
sk|mac_not_macos|Pipswell Desktop v tomto vydaní podporuje macOS (Windows a Linux pribudnú neskôr).
cz|mac_not_macos|Pipswell Desktop v tomto vydání podporuje macOS (Windows a Linux přibudou později).

en|mac_owner_placeholder|The releases address still has the <OWNER> placeholder.\nSet it:  PIPSWELL_RELEASES_URL=https://github.com/<account>/pipswell-desktop-releases/releases/latest/download
sk|mac_owner_placeholder|Adresa vydaní ešte obsahuje zástupný text <OWNER>.\nNastav ju:  PIPSWELL_RELEASES_URL=https://github.com/<account>/pipswell-desktop-releases/releases/latest/download
cz|mac_owner_placeholder|Adresa vydání ještě obsahuje zástupný text <OWNER>.\nNastav ji:  PIPSWELL_RELEASES_URL=https://github.com/<account>/pipswell-desktop-releases/releases/latest/download

en|mac_mt5_missing|MetaTrader 5 is not installed.\n\n  1. Download it:  {page}\n     (macOS installer: {dmg})\n  2. Drag it to Applications, start it and log in to your account once.\n  3. Run this command again.
sk|mac_mt5_missing|MetaTrader 5 nie je nainštalovaný.\n\n  1. Stiahni ho:  {page}\n     (inštalátor pre macOS: {dmg})\n  2. Presuň ho do Aplikácií, spusti ho a raz sa prihlás do svojho účtu.\n  3. Spusti tento príkaz znova.
cz|mac_mt5_missing|MetaTrader 5 není nainstalovaný.\n\n  1. Stáhni si ho:  {page}\n     (instalátor pro macOS: {dmg})\n  2. Přetáhni ho do Aplikací, spusť ho a jednou se přihlas ke svému účtu.\n  3. Spusť tento příkaz znovu.

en|mac_tool_missing|{tool} not found (it ships with macOS).
sk|mac_tool_missing|{tool} sa nenašiel (je súčasťou macOS).
cz|mac_tool_missing|{tool} nebyl nalezen (je součástí macOS).

en|mac_home_is_link|{dir} is a link. Pipswell will not install code there.\nUse a folder of your own:  PIPSWELL_HOME=...
sk|mac_home_is_link|{dir} je odkaz. Pipswell tam kód nenainštaluje.\nPouži vlastný priečinok:  PIPSWELL_HOME=...
cz|mac_home_is_link|{dir} je odkaz. Pipswell tam kód nenainstaluje.\nPoužij vlastní složku:  PIPSWELL_HOME=...

en|mac_other_user|{dir} belongs to another user. Pipswell will not install code there.\nUse a folder of your own:  PIPSWELL_HOME=...
sk|mac_other_user|{dir} patrí inému používateľovi. Pipswell tam kód nenainštaluje.\nPouži vlastný priečinok:  PIPSWELL_HOME=...
cz|mac_other_user|{dir} patří jinému uživateli. Pipswell tam kód nenainstaluje.\nPoužij vlastní složku:  PIPSWELL_HOME=...

en|mac_group_writable|{dir} can be written by other users. Pipswell will not install code there.\nMake it private first:  chmod 700 "{dir}"
sk|mac_group_writable|{dir} môžu zapisovať iní používatelia. Pipswell tam kód nenainštaluje.\nNajprv to nastav ako súkromné:  chmod 700 "{dir}"
cz|mac_group_writable|{dir} mohou zapisovat jiní uživatelé. Pipswell tam kód nenainstaluje.\nNejdřív to nastav jako soukromé:  chmod 700 "{dir}"

en|mac_foreign_link|{path} is a link Pipswell did not make. Pipswell will not install code there.
sk|mac_foreign_link|{path} je odkaz, ktorý Pipswell nevytvoril. Pipswell tam kód nenainštaluje.
cz|mac_foreign_link|{path} je odkaz, který Pipswell nevytvořil. Pipswell tam kód nenainstaluje.

en|mac_link_outside|{path} points outside {dir}. Pipswell will not install code there.
sk|mac_link_outside|{path} ukazuje mimo {dir}. Pipswell tam kód nenainštaluje.
cz|mac_link_outside|{path} ukazuje mimo {dir}. Pipswell tam kód nenainstaluje.

en|mac_unsupported_cpu|Unsupported processor: {cpu}.
sk|mac_unsupported_cpu|Nepodporovaný procesor: {cpu}.
cz|mac_unsupported_cpu|Nepodporovaný procesor: {cpu}.

en|mac_uv_sha|The uv installer does not match its pinned SHA256. Nothing was run.
sk|mac_uv_sha|Inštalátor uv nezodpovedá očakávanému SHA256. Nič sa nespustilo.
cz|mac_uv_sha|Instalátor uv neodpovídá očekávanému SHA256. Nic se nespustilo.

en|mac_downgrade|{name} offers {version}, older than the installed {current}. Nothing was changed.\nTo go back on purpose:  PIPSWELL_ALLOW_DOWNGRADE=1
sk|mac_downgrade|{name} ponúka {version}, staršiu než nainštalovanú {current}. Nič sa nezmenilo.\nAk sa chceš vrátiť zámerne:  PIPSWELL_ALLOW_DOWNGRADE=1
cz|mac_downgrade|{name} nabízí {version}, starší než nainstalovanou {current}. Nic se nezměnilo.\nPokud se chceš vrátit záměrně:  PIPSWELL_ALLOW_DOWNGRADE=1

en|mac_path_note|Note: {dir} is not on your PATH. Run  {dir}/pipswell  directly, or add to your shell profile:
sk|mac_path_note|Poznámka: {dir} nie je v tvojej PATH. Spúšťaj  {dir}/pipswell  priamo alebo pridaj do profilu shellu:
cz|mac_path_note|Poznámka: {dir} není ve tvé PATH. Spouštěj  {dir}/pipswell  přímo, nebo přidej do profilu shellu:

en|mac_bin_unwritable|Note: {dir} cannot be written (owned by another user). The command is  "{cli}"
sk|mac_bin_unwritable|Poznámka: do {dir} sa nedá zapisovať (patrí inému používateľovi). Príkaz je  "{cli}"
cz|mac_bin_unwritable|Poznámka: do {dir} nelze zapisovat (patří jinému uživateli). Příkaz je  "{cli}"
MSGS

# lang_of_code CODE: sk, cz or empty, from a language code such as sk, sk-SK, sk_SK.UTF-8, cs, cs-CZ
lang_of_code() {
    local code
    code="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
    case "$code" in
        sk|sk[-_.@]*) printf 'sk\n' ;;
        cs|cs[-_.@]*) printf 'cz\n' ;;
        *) printf '\n' ;;
    esac
}

# detect_lang: the language of the messages: PIPSWELL_LANG (sk, cz or en) wins; any other value is ignored. Then the first entry of
# the macOS language list (`defaults read -g AppleLanguages`), then LC_ALL / LC_MESSAGES / LANG. Else en. Never fails: `defaults`
# may be missing or may error, and this runs under set -euo pipefail.
detect_lang() {
    local first="" code="" var lang
    case "${PIPSWELL_LANG:-}" in
        sk|cz|en) printf '%s\n' "$PIPSWELL_LANG"; return 0 ;;
    esac
    first="$( { defaults read -g AppleLanguages 2>/dev/null || true; } 2>/dev/null | tr -d '(), "' | sed -n '/./{p;q;}' || true)"
    if [ -n "$first" ]; then
        code="$first"
    else
        for var in "${LC_ALL:-}" "${LC_MESSAGES:-}" "${LANG:-}"; do
            if [ -n "$var" ]; then code="$var"; break; fi
        done
    fi
    lang="$(lang_of_code "$code")"
    printf '%s\n' "${lang:-en}"
}

# msg KEY [NAME=VALUE ...]: the text of KEY in UI_LANG (English when it has none), \n made a line break, each {NAME} filled
# once, left to right (a value is never searched for further names). No trailing newline.
msg() {
    local key="$1" lang line text="" out="" rest name pair found
    shift
    for lang in "${UI_LANG:-en}" en; do
        while IFS= read -r line; do
            case "$line" in
                "$lang|$key|"*) text="${line#"$lang|$key|"}"; break 2 ;;
            esac
        done <<< "$MSG_TABLE"
    done
    text="$(printf '%b' "$text")"
    rest="$text"
    while [[ "$rest" == *"{"*"}"* ]]; do
        out="$out${rest%%\{*}"
        rest="${rest#*\{}"
        name="${rest%%\}*}"
        found=0
        for pair in "$@"; do
            if [ "${pair%%=*}" = "$name" ]; then out="$out${pair#*=}"; found=1; break; fi
        done
        if [ "$found" = 0 ]; then out="${out}{${name}}"; fi
        rest="${rest#*\}}"
    done
    printf '%s' "$out$rest"
}
UI_LANG="$(detect_lang)"
# ---- messages (end)
say()  { printf '%s\n' "$*"; }
die()  { printf '\n%s\n' "$*" >&2; exit 1; }

# The releases repo (jarsim/pipswell-desktop-releases). It is PRIVATE until the owner makes it
# public; until then an anonymous download fails. PIPSWELL_RELEASES_URL=... overrides the address.
DEFAULT_RELEASES_URL="https://github.com/jarsim/pipswell-desktop-releases/releases/latest/download"
# the beta channel: its pointers sit in one rolling release (tag beta), each version's zip in its own release
DEFAULT_BETA_POINTERS_URL="https://github.com/jarsim/pipswell-desktop-releases/releases/download/beta"
DEFAULT_TAGS_URL="https://github.com/jarsim/pipswell-desktop-releases/releases/download"
# The owner's offline Ed25519 release key (public half, base64 of the 32 raw bytes); the same value as in
# pipswell/updater.py and install.ps1. While it is the placeholder this installer refuses everything.
RELEASE_PUBLIC_KEY="xI0yneFg+9DhXhAOhe05+PSNsp450TsVIAQoK7kLuxk="
# The channel: PIPSWELL_CHANNEL, else the one a previous install stored in app/channel (so re-running the installer
# keeps a beta install on beta), else stable. Mirrors pipswell/updater.py channel / stored_channel. Only an exact
# "stable" or "beta" is accepted from either; nothing is fetched before the folder checks below.
HOME_DIR="${PIPSWELL_HOME:-$HOME/Library/Application Support/Pipswell}"
APP_ROOT="$HOME_DIR/app"
CHANNEL="${PIPSWELL_CHANNEL:-}"
if [ -z "$CHANNEL" ] && [ -f "$APP_ROOT/channel" ] && [ ! -L "$APP_ROOT/channel" ]; then
    CHANNEL="$(head -n 1 "$APP_ROOT/channel" | head -c 64 || true)"
    CHANNEL="${CHANNEL#"${CHANNEL%%[![:space:]]*}"}"
    CHANNEL="${CHANNEL%"${CHANNEL##*[![:space:]]}"}"
    case "$CHANNEL" in
        ""|stable|beta) ;;
        *) die "$(msg channel_stored_bad file="$APP_ROOT/channel" value="$CHANNEL")" ;;
    esac
fi
CHANNEL="${CHANNEL:-stable}"
case "$CHANNEL" in
    stable) RELEASES_URL="$DEFAULT_RELEASES_URL" ;;
    beta)   RELEASES_URL="$DEFAULT_BETA_POINTERS_URL" ;;
    *)      die "$(msg channel_env_bad value="$CHANNEL")" ;;
esac
RELEASES_URL="${PIPSWELL_RELEASES_URL:-$RELEASES_URL}"
RELEASES_URL="${RELEASES_URL%/}"

# uv is fetched from Astral at this exact version (the install script of that version, not "latest")
UV_VERSION="0.11.6"
# SHA256 of that version's install.sh (computed 2026-10-18); the script is verified before it runs
UV_INSTALLER_SHA256="02f6fdf8077f97f7bbd901de06054a65e7aefbd54432c8a83784d42a3e360a45"
PYTHON_VERSION="3.13"
MT5_APP="/Applications/MetaTrader 5.app"
MT5_PAGE="https://www.metatrader5.com/en/download"
MT5_DMG="https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/MetaTrader5.dmg"

# version_key V: the numbers pipswell/updater.py version_key compares, space-separated: the release padded
# to 4 numbers, then "0 0" for a final release, "-1 N" for bN and "-2 N" for .devN (0.2.0.dev28 < 0.2.0b1 < 0.2.0).
# After - or + : ignored.
version_key() {
    local base="${1%%[-+]*}" d out=""
    if [[ "$base" =~ ^([0-9]+(\.[0-9]+)*)(\.dev([0-9]+)|b([0-9]+))?$ ]]; then
        local rel="${BASH_REMATCH[1]}" dev="${BASH_REMATCH[4]}" beta="${BASH_REMATCH[5]}" n=0
        for d in ${rel//./ }; do out="$out $((10#$d))"; n=$((n + 1)); done
        while [ "$n" -lt 4 ]; do out="$out 0"; n=$((n + 1)); done
        if [ -n "$dev" ]; then out="$out -2 $((10#$dev))"
        elif [ -n "$beta" ]; then out="$out -1 $((10#$beta))"
        else out="$out 0 0"; fi
    else
        for d in $(printf '%s' "$base" | tr -c '0-9' ' '); do out="$out $((10#$d))"; done
    fi
    printf '%s\n' "${out# }"
}
# version_lt A B: whether version A is older than B (number by number; a shorter equal prefix is older)
version_lt() {
    local a b i
    read -r -a a <<< "$(version_key "$1")"
    read -r -a b <<< "$(version_key "$2")"
    for ((i = 0; i < ${#a[@]} && i < ${#b[@]}; i++)); do
        if ((a[i] < b[i])); then return 0; fi
        if ((a[i] > b[i])); then return 1; fi
    done
    [ "${#a[@]}" -lt "${#b[@]}" ]
}
# reuse_ok DIR SHA VERSION CURRENT: whether app/<VERSION> may be used as it is: its .installed holds the SHA256
# verified for this release, or it is the one already running with its .venv (switching to it activates nothing
# new; folders made by older updaters carry no .installed). A bare .installed no longer skips the download (pentest M2).
# The stamp ties a folder to its release; it is no defence against someone who can write app/ (the hash is public).
# Either way it needs its .venv (as pipswell/updater.py unpack): a stamped folder without one is unpacked again.
reuse_ok() {
    [ -d "$1/.venv" ] || return 1
    if [ -f "$1/.installed" ] && [ "$(head -n 1 "$1/.installed")" = "$2" ]; then return 0; fi
    [ -n "$4" ] && [ "$3" = "$4" ]
}

# private_dir DIR: refuse a folder that belongs to another user or that others can write: a shared, writable
# PIPSWELL_HOME would let another user plant app/<ver>/.venv plus a .installed (the SHA256 is public). Mirrors
# pipswell/updater.py folder_problem; the Windows installer locks its folder down with icacls instead.
# ls -ldL, not stat: macOS and GNU stat take different flags.
private_dir() {
    local m
    [ -O "$1" ] || die "$(msg mac_other_user dir="$1")"
    m="$(ls -ldL "$1")"
    if [ "${m:5:1}" = w ] || [ "${m:8:1}" = w ]; then
        die "$(msg mac_group_writable dir="$1")"
    fi
}

# app_entries_ok APP UV: everything directly in app/ (bin, python, uv-cache, each version folder) and app/bin/uv
# pass private_dir; the only links allowed are current / .current.new pointing into app/ (a link can be pointed
# elsewhere after the check). Mirrors pipswell/updater.py trust_problem; deeper files are not walked.
app_entries_ok() {
    local item
    for item in "$1"/* "$1"/.[!.]*; do
        [ -e "$item" ] || [ -L "$item" ] || continue
        if [ -L "$item" ]; then
            case "${item##*/}" in
                current|.current.new) ;;
                *) die "$(msg mac_foreign_link path="$item")" ;;
            esac
            case "$(readlink "$item")" in
                */*|.|..|"") die "$(msg mac_link_outside path="$item" dir="$1")" ;;
            esac
            continue
        fi
        private_dir "$item"
    done
    [ ! -e "$2" ] || private_dir "$2"
}

# require_release_key KEY: refuse while KEY is not a real Ed25519 public key (43 base64 characters and "="): the
# placeholder in a build the owner has not switched on, or garbage. Nothing is checked or installed without one.
require_release_key() {
    case "$1" in
        REPLACE-WITH-*) die "$(msg key_none)" ;;
    esac
    [[ "$1" =~ ^[A-Za-z0-9+/]{43}=$ ]] || die "$(msg key_bad)"
}

# verify_pointer POINTER SIG: the release list is signed by the release key (RELEASE_PUBLIC_KEY) FOR THIS NAME (the
# signature covers the file's name, so a beta list renamed to the stable name fails), else die. Runs the
# managed Python directly (uv python find, no uv run: nothing is created in the uv cache) with -B -I: no bytecode, no
# user site, nothing imported from the current folder. Mirrors pipswell/updater.py verify_pointer.
verify_pointer() {
    local py
    py="$("$UV" python find --managed-python --no-project "$PYTHON_VERSION")" || die "$(msg no_python)"
    # uv also looks in virtual environments (an active one, a .venv in the current folder): only a Python inside the
    # app folder (private, checked above) may run here
    case "$(cd -P "$(dirname "$py")" 2>/dev/null && pwd)/" in
        "$(cd -P "$APP_ROOT" && pwd)"/*) ;;
        *) die "$(msg python_foreign python="$py")" ;;
    esac
    cat > "$WORK/verify_pointer.py" <<'VERIFY_PY'
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
VERIFY_PY
    "$py" -B -I "$WORK/verify_pointer.py" "$RELEASE_PUBLIC_KEY" "$1" "$2" "$(basename "$1")" \
        || die "$(msg sig_invalid name="$(basename "$1")")"
}

# read_pointer NAME: fetch the release list NAME and NAME.sig from RELEASES_URL, verify the signature, then read
# VERSION FILE SHA from it. Nothing of an unsigned or wrongly signed list is read.
read_pointer() {
    fetch "$WORK/$1" "$RELEASES_URL/$1" || die "$(msg pointer_unreadable url="$RELEASES_URL/$1")"
    fetch "$WORK/$1.sig" "$RELEASES_URL/$1.sig" || die "$(msg pointer_no_sig name="$1" url="$RELEASES_URL/$1")"
    verify_pointer "$WORK/$1" "$WORK/$1.sig"
    read -r VERSION FILE SHA < "$WORK/$1" || true
}

# pointer_name PLATFORM: the release list of this channel (the beta channel's has beta- in it)
pointer_name() {
    if [ "$CHANNEL" = beta ]; then printf 'latest-beta-%s.txt\n' "$1"; else printf 'latest-%s.txt\n' "$1"; fi
}

# asset_base VERSION: where the zip and its .sha256 are: with the lists (PIPSWELL_RELEASES_URL set, or stable), else
# for a beta in that version's own release (VERSION has passed the shape check, so it adds no path or query)
asset_base() {
    if [ -n "${PIPSWELL_RELEASES_URL:-}" ] || [ "$CHANNEL" != beta ]; then printf '%s\n' "$RELEASES_URL"
    else printf '%s/v%s\n' "$DEFAULT_TAGS_URL" "$1"; fi
}

[ "$(uname -s)" = Darwin ] || die "$(msg mac_not_macos)"

case "$RELEASES_URL" in
    *"<OWNER>"*) die "$(msg mac_owner_placeholder)" ;;
esac
# Parsed, not prefix-matched: https://host/... without credentials, or plain http for the exact
# host 127.0.0.1 only (a local test server). `http://127.0.0.1.evil.example` and `https://user@host`
# both begin like an allowed address.
URL_RE='^(https|http)://([^/?#@[:space:]]+)(/[^[:space:]]*)?$'
[[ "$RELEASES_URL" =~ $URL_RE ]] || die "$(msg url_not_https_creds)"
URL_SCHEME="${BASH_REMATCH[1]}"; URL_HOST="${BASH_REMATCH[2]%%:*}"
if [ "$URL_SCHEME" = http ]; then
    [ "$URL_HOST" = 127.0.0.1 ] || die "$(msg url_not_https)"
    PROTO='=http,https'          # a local test server; redirects below are still https only
else
    PROTO='=https'
fi
# every download: the protocol is fixed, and a redirect may lead to https only
fetch() { curl -fsSL --proto "$PROTO" --proto-redir '=https' -o "$@"; }
# no signing key, no install: refused before anything is written
require_release_key "$RELEASE_PUBLIC_KEY"

if [ ! -x "$MT5_APP/Contents/SharedSupport/wine/bin/wine" ]; then
    die "$(msg mac_mt5_missing page="$MT5_PAGE" dmg="$MT5_DMG")"
fi

for tool in curl unzip shasum; do
    command -v "$tool" >/dev/null || die "$(msg mac_tool_missing tool="$tool")"
done

UV="$APP_ROOT/bin/uv"
# The command lives in the app folder (always ours to write). ~/.local/bin gets a link to it when that
# folder can be used: on some Macs another installer created ~/.local as root, and the install must not
# fail (or ask for sudo) because of that.
CLI="$APP_ROOT/bin/pipswell"
BIN_DIR="$HOME/.local/bin"
# The folder holds the code the jobs run and the secrets (ADMIN_TOKEN, BRIDGE_SECRET, ledgers): this user only.
# Neither it nor app/ may be a link (it could be pointed elsewhere after the check); a new one is made private
# from the start (umask 077), so nobody can put anything in it before chmod.
for d in "$HOME_DIR" "$APP_ROOT"; do
    [ ! -L "$d" ] || die "$(msg mac_home_is_link dir="$d")"
done
if [ -e "$HOME_DIR" ]; then
    private_dir "$HOME_DIR"
else
    (umask 077 && mkdir -p "$HOME_DIR")
    chmod 700 "$HOME_DIR"
    private_dir "$HOME_DIR"
fi
if [ -e "$APP_ROOT" ]; then
    private_dir "$APP_ROOT"
    app_entries_ok "$APP_ROOT" "$UV"
else
    (umask 077 && mkdir "$APP_ROOT")
fi
mkdir -p "$APP_ROOT/bin"
# uv keeps Python, its cache and any Python links in the app folder too: nothing under ~/.local (which
# may belong to root on some Macs) and nothing to clean up elsewhere on uninstall.
export UV_PYTHON_INSTALL_DIR="$APP_ROOT/python" UV_CACHE_DIR="$APP_ROOT/uv-cache" UV_PYTHON_BIN_DIR="$APP_ROOT/bin"
export UV_NO_MODIFY_PATH=1
# no uv.toml (the current folder's, the user's) may redirect the package index or the Python download
export UV_NO_CONFIG=1

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---- uv, into the app folder only -------------------------------------------------------------
if [ ! -x "$UV" ]; then
    say "$(msg installing_uv version="$UV_VERSION" dir="$APP_ROOT/bin")"
    curl -fsSL --proto '=https' --proto-redir '=https' -o "$WORK/uv-install.sh" "https://astral.sh/uv/$UV_VERSION/install.sh"
    GOT_UV="$(shasum -a 256 "$WORK/uv-install.sh" | cut -d' ' -f1)"
    [ "$GOT_UV" = "$UV_INSTALLER_SHA256" ] || die "$(msg mac_uv_sha)"
    # UV_UNMANAGED_INSTALL: put the binary exactly here, edit no shell profile, no PATH changes
    UV_UNMANAGED_INSTALL="$APP_ROOT/bin" sh "$WORK/uv-install.sh" >/dev/null
    [ -x "$UV" ] || die "$(msg uv_not_installed dir="$APP_ROOT/bin")"
fi
say "$(msg python_step version="$PYTHON_VERSION")"
"$UV" python install "$PYTHON_VERSION"

# ---- the release: version, file and hash come from the SIGNED latest-<platform>.txt; the zip must match them
# The app ships compiled, one build per processor: Apple silicon (arm64) or Intel (x86_64).
case "$(uname -m)" in
    arm64)  PLATFORM=macos-arm64 ;;
    x86_64) PLATFORM=macos-x64 ;;
    *)      die "$(msg mac_unsupported_cpu cpu="$(uname -m)")" ;;
esac
LATEST="$(pointer_name "$PLATFORM")"
say "$(msg looking_release channel="$CHANNEL")"
read_pointer "$LATEST"
[[ "${VERSION:-}" =~ ^[0-9]+(\.[0-9]+){1,3}([-+.][0-9A-Za-z.]+|b[0-9]+)?$ ]] || die "$(msg bad_version name="$LATEST")"
[ "${FILE:-}" = "pipswell-desktop-$VERSION-$PLATFORM.zip" ] || die "$(msg bad_file name="$LATEST")"
[[ "${SHA:-}" =~ ^[0-9a-f]{64}$ ]] || die "$(msg bad_sha name="$LATEST")"

# The stable channel never takes a beta (bN) or dev (.devN) build: a pointer from another channel is no stable release.
# The one exception is a dev build of the 0.2.0 line (the dev28 transition; tools/build_release.py DEV_ON_STABLE_LINE,
# pipswell/updater.py check_channel_version).
STABLE_BASE="${VERSION%%[-+]*}"
if [ "$CHANNEL" = stable ] && [[ "$STABLE_BASE" =~ ^[0-9]+(\.[0-9]+)*(\.dev[0-9]+|b[0-9]+)$ ]] && ! [[ "$STABLE_BASE" =~ ^0\.2\.0\.dev[0-9]+$ ]]; then
    die "$(msg stable_refuses name="$LATEST" version="$VERSION")"
fi

CURRENT_VERSION=""
if [ -L "$APP_ROOT/current" ]; then CURRENT_VERSION="$(basename "$(readlink "$APP_ROOT/current")")"; fi
# A replayed or older release pointer must not move an install back onto an older (maybe vulnerable) build.
if [ -n "$CURRENT_VERSION" ] && version_lt "$VERSION" "$CURRENT_VERSION" && [ "${PIPSWELL_ALLOW_DOWNGRADE:-}" != 1 ]; then
    die "$(msg mac_downgrade name="$LATEST" version="$VERSION" current="$CURRENT_VERSION")"
fi

TARGET="$APP_ROOT/$VERSION"
if reuse_ok "$TARGET" "$SHA" "$VERSION" "$CURRENT_VERSION"; then
    say "$(msg already_unpacked version="$VERSION")"
else
    say "$(msg downloading version="$VERSION")"
    ASSETS="$(asset_base "$VERSION")"
    fetch "$WORK/$FILE" "$ASSETS/$FILE"
    fetch "$WORK/$FILE.sha256" "$ASSETS/$FILE.sha256"
    GOT="$(shasum -a 256 "$WORK/$FILE" | cut -d' ' -f1)"
    SIDE="$(cut -d' ' -f1 < "$WORK/$FILE.sha256")"
    [ "$GOT" = "$SHA" ] || die "$(msg sha_mismatch name="$LATEST")"
    [ "$SIDE" = "$SHA" ] || die "$(msg sha_side file="$FILE" name="$LATEST")"
    say "$(msg sha_verified)"
    # Unpack with the checks `pipswell update` applies (pipswell/updater.py extract): no symlink, no
    # absolute path, no `..`, exactly one top-level folder. `unzip` would follow what the zip says.
    # Mirrors updater.extract; the hash above already says the zip is the published one.
    cat > "$WORK/extract.py" <<'PY'
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
        if i.filename.startswith(("/", "\\")) or ".." in Path(i.filename).parts or "\\" in i.filename:
            sys.exit(f"unsafe path in the release zip: {i.filename}")
        if stat.S_ISLNK(i.external_attr >> 16):
            sys.exit(f"symlink in the release zip: {i.filename}")
    dest.mkdir(parents=True, exist_ok=False)
    for i in infos:
        target = dest / i.filename
        if i.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(z.read(i))
        target.chmod(0o755 if (i.external_attr >> 16) & 0o100 else 0o644)
PY
    "$UV" run --no-project --python "$PYTHON_VERSION" python -I "$WORK/extract.py" "$WORK/$FILE" "$WORK/x" \
        || die "$(msg zip_unsafe)"
    [ -d "$WORK/x/pipswell-desktop-$VERSION" ] || die "$(msg layout_bad)"
    rm -rf "$TARGET"
    mv "$WORK/x/pipswell-desktop-$VERSION" "$TARGET"
    say "$(msg installing_packages)"
    if ! "$UV" sync --frozen --no-dev --python "$PYTHON_VERSION" --project "$TARGET"; then
        rm -rf "$TARGET"
        die "$(msg sync_failed)"
    fi
    printf '%s\n' "$SHA" > "$TARGET/.installed"
fi

# ---- switch to it: one symlink, relative, replaced in a single step ---------------------------
rm -f "$APP_ROOT/.current.new"
ln -s "$VERSION" "$APP_ROOT/.current.new"
mv -fh "$APP_ROOT/.current.new" "$APP_ROOT/current"

# ---- the `pipswell` command: a tiny wrapper, so updates never leave it pointing at old code ----
{
    printf '#!/bin/bash\n# written by the Pipswell installer\n'
    [ -z "${PIPSWELL_HOME:-}" ] || printf 'export PIPSWELL_HOME=%q\n' "$PIPSWELL_HOME"
    # -I: isolated mode (no current folder, no PYTHON* variables, no user site on sys.path), so a
    # `pipswell/` or `yaml.py` in whatever folder the command is typed in can never be imported instead
    printf 'exec %q -I -m pipswell "$@"\n' "$APP_ROOT/current/.venv/bin/python"
} > "$CLI.new"
chmod 755 "$CLI.new"
mv -f "$CLI.new" "$CLI"
# Remember the channel: `pipswell update` and the portal's update check read app/channel when PIPSWELL_CHANNEL is
# not set (pipswell/updater.py channel). One line, written beside the other files of app/ (private, checked above).
printf '%s\n' "$CHANNEL" > "$APP_ROOT/.channel.new"
mv -f "$APP_ROOT/.channel.new" "$APP_ROOT/channel"
if mkdir -p "$BIN_DIR" 2>/dev/null && [ -w "$BIN_DIR" ] && ln -sfn "$CLI" "$BIN_DIR/pipswell" 2>/dev/null; then
    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *) say "$(msg mac_path_note dir="$BIN_DIR")"
           say "      export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
    esac
else
    say "$(msg mac_bin_unwritable dir="$BIN_DIR" cli="$CLI")"
fi

# ---- set up, (re)start, open --------------------------------------------------------------------
"$CLI" setup
"$CLI" restart
"$CLI" open || true
say ""
say "$(msg running version="$VERSION")"
say "  pipswell status    pipswell doctor    pipswell stop    pipswell update    pipswell uninstall"
say "$(msg mac_uninstall_where)"
