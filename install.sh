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
#   PIPSWELL_RELEASES_URL   where latest-<platform>.txt, the zip and its .sha256 live
#                           (default: the placeholder below; set the real address, see installer/README.md)
#   PIPSWELL_HOME           install somewhere else than ~/Library/Application Support/Pipswell
set -euo pipefail

# The releases repo (jarsim/pipswell-desktop-releases). It is PRIVATE until the owner makes it
# public; until then an anonymous download fails. PIPSWELL_RELEASES_URL=... overrides the address.
DEFAULT_RELEASES_URL="https://github.com/jarsim/pipswell-desktop-releases/releases/latest/download"
RELEASES_URL="${PIPSWELL_RELEASES_URL:-$DEFAULT_RELEASES_URL}"
RELEASES_URL="${RELEASES_URL%/}"

# uv is fetched from Astral at this exact version (the install script of that version, not "latest")
UV_VERSION="0.11.6"
# SHA256 of that version's install.sh (computed 2026-10-18); the script is verified before it runs
UV_INSTALLER_SHA256="02f6fdf8077f97f7bbd901de06054a65e7aefbd54432c8a83784d42a3e360a45"
PYTHON_VERSION="3.13"
MT5_APP="/Applications/MetaTrader 5.app"
MT5_PAGE="https://www.metatrader5.com/en/download"
MT5_DMG="https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/MetaTrader5.dmg"

say()  { printf '%s\n' "$*"; }
die()  { printf '\n%s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || die "Pipswell Desktop supports macOS in this release (Windows and Linux come later)."

case "$RELEASES_URL" in
    *"<OWNER>"*) die "The releases address still has the <OWNER> placeholder.
Set it:  PIPSWELL_RELEASES_URL=https://github.com/<account>/pipswell-desktop-releases/releases/latest/download" ;;
esac
# Parsed, not prefix-matched: https://host/... without credentials, or plain http for the exact
# host 127.0.0.1 only (a local test server). `http://127.0.0.1.evil.example` and `https://user@host`
# both begin like an allowed address.
URL_RE='^(https|http)://([^/?#@[:space:]]+)(/[^[:space:]]*)?$'
[[ "$RELEASES_URL" =~ $URL_RE ]] || die "PIPSWELL_RELEASES_URL must be an https:// address (no credentials)."
URL_SCHEME="${BASH_REMATCH[1]}"; URL_HOST="${BASH_REMATCH[2]%%:*}"
if [ "$URL_SCHEME" = http ]; then
    [ "$URL_HOST" = 127.0.0.1 ] || die "PIPSWELL_RELEASES_URL must be an https:// address."
    PROTO='=http,https'          # a local test server; redirects below are still https only
else
    PROTO='=https'
fi
# every download: the protocol is fixed, and a redirect may lead to https only
fetch() { curl -fsSL --proto "$PROTO" --proto-redir '=https' -o "$@"; }

if [ ! -x "$MT5_APP/Contents/SharedSupport/wine/bin/wine" ]; then
    die "MetaTrader 5 is not installed.

  1. Download it:  $MT5_PAGE
     (macOS installer: $MT5_DMG)
  2. Drag it to Applications, start it and log in to your account once.
  3. Run this command again."
fi

for tool in curl unzip shasum; do
    command -v "$tool" >/dev/null || die "$tool not found (it ships with macOS)."
done

HOME_DIR="${PIPSWELL_HOME:-$HOME/Library/Application Support/Pipswell}"
APP_ROOT="$HOME_DIR/app"
UV="$APP_ROOT/bin/uv"
# The command lives in the app folder (always ours to write). ~/.local/bin gets a link to it when that
# folder can be used: on some Macs another installer created ~/.local as root, and the install must not
# fail (or ask for sudo) because of that.
CLI="$APP_ROOT/bin/pipswell"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$APP_ROOT/bin"
# uv keeps Python, its cache and any Python links in the app folder too: nothing under ~/.local (which
# may belong to root on some Macs) and nothing to clean up elsewhere on uninstall.
export UV_PYTHON_INSTALL_DIR="$APP_ROOT/python" UV_CACHE_DIR="$APP_ROOT/uv-cache" UV_PYTHON_BIN_DIR="$APP_ROOT/bin"
export UV_NO_MODIFY_PATH=1

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---- uv, into the app folder only -------------------------------------------------------------
if [ ! -x "$UV" ]; then
    say "Installing uv $UV_VERSION into $APP_ROOT/bin ..."
    curl -fsSL --proto '=https' --proto-redir '=https' -o "$WORK/uv-install.sh" "https://astral.sh/uv/$UV_VERSION/install.sh"
    GOT_UV="$(shasum -a 256 "$WORK/uv-install.sh" | cut -d' ' -f1)"
    [ "$GOT_UV" = "$UV_INSTALLER_SHA256" ] || die "The uv installer does not match its pinned SHA256. Nothing was run."
    # UV_UNMANAGED_INSTALL: put the binary exactly here, edit no shell profile, no PATH changes
    UV_UNMANAGED_INSTALL="$APP_ROOT/bin" sh "$WORK/uv-install.sh" >/dev/null
    [ -x "$UV" ] || die "uv did not install into $APP_ROOT/bin."
fi
say "Python $PYTHON_VERSION ..."
"$UV" python install "$PYTHON_VERSION"

# ---- the release: version, file and hash come from latest-<platform>.txt; the zip must match them
# The app ships compiled, one build per processor: Apple silicon (arm64) or Intel (x86_64).
case "$(uname -m)" in
    arm64)  PLATFORM=macos-arm64 ;;
    x86_64) PLATFORM=macos-x64 ;;
    *)      die "Unsupported processor: $(uname -m)." ;;
esac
LATEST="latest-$PLATFORM.txt"
say "Looking for the newest release ..."
fetch "$WORK/$LATEST" "$RELEASES_URL/$LATEST" || die "Could not read $RELEASES_URL/$LATEST"
read -r VERSION FILE SHA < "$WORK/$LATEST" || true
[[ "${VERSION:-}" =~ ^[0-9]+(\.[0-9]+){1,3}([-+.][0-9A-Za-z.]+)?$ ]] || die "$LATEST: bad version."
[ "${FILE:-}" = "pipswell-desktop-$VERSION-$PLATFORM.zip" ] || die "$LATEST: bad file name."
[[ "${SHA:-}" =~ ^[0-9a-f]{64}$ ]] || die "$LATEST: bad SHA256."

TARGET="$APP_ROOT/$VERSION"
if [ -f "$TARGET/.installed" ]; then
    say "Pipswell $VERSION is already unpacked."
else
    say "Downloading Pipswell $VERSION ..."
    fetch "$WORK/$FILE" "$RELEASES_URL/$FILE"
    fetch "$WORK/$FILE.sha256" "$RELEASES_URL/$FILE.sha256"
    GOT="$(shasum -a 256 "$WORK/$FILE" | cut -d' ' -f1)"
    SIDE="$(cut -d' ' -f1 < "$WORK/$FILE.sha256")"
    [ "$GOT" = "$SHA" ] || die "The download does not match the SHA256 in $LATEST. Nothing was installed."
    [ "$SIDE" = "$SHA" ] || die "$FILE.sha256 disagrees with $LATEST. Nothing was installed."
    say "SHA256 verified."
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
        || die "The release zip failed the safety checks. Nothing was installed."
    [ -d "$WORK/x/pipswell-desktop-$VERSION" ] || die "Unexpected release layout."
    rm -rf "$TARGET"
    mv "$WORK/x/pipswell-desktop-$VERSION" "$TARGET"
    say "Installing the Python packages (locked versions) ..."
    if ! "$UV" sync --frozen --no-dev --python "$PYTHON_VERSION" --project "$TARGET"; then
        rm -rf "$TARGET"
        die "uv sync failed; the previous version (if any) is untouched."
    fi
    touch "$TARGET/.installed"
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
if mkdir -p "$BIN_DIR" 2>/dev/null && [ -w "$BIN_DIR" ] && ln -sfn "$CLI" "$BIN_DIR/pipswell" 2>/dev/null; then
    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *) say "Note: $BIN_DIR is not on your PATH. Run  $BIN_DIR/pipswell  directly, or add to your shell profile:"
           say "      export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
    esac
else
    say "Note: $BIN_DIR cannot be written (owned by another user). The command is  \"$CLI\""
fi

# ---- set up, (re)start, open --------------------------------------------------------------------
"$CLI" setup
"$CLI" restart
"$CLI" open || true
say ""
say "Pipswell $VERSION is running. Everything is DRY: nothing real is placed until you switch it off yourself."
say "  pipswell status    pipswell doctor    pipswell stop    pipswell update    pipswell uninstall"
