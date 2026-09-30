#!/bin/sh
set -eu

BURN_REPO="${BURN_REPO:-https://github.com/burnlang/burn}"
BURN_REF="${BURN_REF:-master}"
ASH_REPO="${ASH_REPO:-https://github.com/burnlang/ash}"
ASH_REF="${ASH_REF:-master}"
BURNUP_URL="${BURNUP_URL:-https://raw.githubusercontent.com/burnlang/burnup/master/install.sh}"
PREFIX="${BURN_HOME:-$HOME/.burn}"
FROM_SOURCE=0
MODIFY_PATH=1
INSTALL_RUST=0
WITH_ASH=1
QUIET=0
ACTION=install

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD="$(printf '\033[1m')"
    RED="$(printf '\033[31m')"
    GREEN="$(printf '\033[32m')"
    YELLOW="$(printf '\033[33m')"
    RESET="$(printf '\033[0m')"
else
    BOLD=""
    RED=""
    GREEN=""
    YELLOW=""
    RESET=""
fi

say() {
    if [ "$QUIET" -eq 0 ]; then
        printf '%s\n' "$*"
    fi
}

step() {
    say "${BOLD}==>${RESET} $*"
}

warn() {
    printf '%s\n' "${YELLOW}warning:${RESET} $*" >&2
}

die() {
    printf '%s\n' "${RED}error:${RESET} $*" >&2
    exit 1
}

usage() {
    cat <<EOF
burnup - installs and updates the Burn toolchain

Installs burn, burni (interpreter), burnc (compiler), burnfmt (formatter),
burn-lsp (language server), bvm (the Burn virtual machine), ash (the package
manager) and burnup itself into \$BURN_HOME/bin (default: ~/.burn/bin).

Usage:
  burnup [install] [options]   install, or reinstall, the toolchain
  burnup update [options]      update Burn, ash and burnup to the newest versions
  burnup uninstall             remove Burn, installed packages and commands
  burnup show                  print the installed versions
  burnup help                  show this help

Options:
  --prefix <dir>      install into <dir> instead of ~/.burn
  --ref <git ref>     Burn branch, tag or commit to build (default: master)
  --ash-ref <ref>     ash branch, tag or commit to build (default: master)
  --from-source       build Burn from source instead of downloading a release
  --install-rust      install Rust with rustup if cargo is missing
  --no-ash            do not install ash
  --no-modify-path    do not add the bin directory to your shell profile
  -q, --quiet         only print errors

Environment:
  BURN_HOME           installation directory (same as --prefix)
  BURN_REPO, BURN_REF where to get Burn from
  ASH_REPO, ASH_REF   where to get ash from

Examples:
  curl -fsSL https://raw.githubusercontent.com/burnlang/burnup/master/install.sh | sh
  curl -fsSL https://raw.githubusercontent.com/burnlang/burnup/master/install.sh | sh -s -- --from-source
  burnup update
EOF
}

case "${1:-}" in
    install | update | uninstall | show | help)
        ACTION="$1"
        shift
        ;;
    self-update)
        ACTION=update
        shift
        ;;
esac

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            [ $# -ge 2 ] || die "--prefix needs a directory"
            PREFIX="$2"
            shift 2
            ;;
        --prefix=*)
            PREFIX="${1#--prefix=}"
            shift
            ;;
        --ref)
            [ $# -ge 2 ] || die "--ref needs a value"
            BURN_REF="$2"
            shift 2
            ;;
        --ref=*)
            BURN_REF="${1#--ref=}"
            shift
            ;;
        --ash-ref)
            [ $# -ge 2 ] || die "--ash-ref needs a value"
            ASH_REF="$2"
            shift 2
            ;;
        --ash-ref=*)
            ASH_REF="${1#--ash-ref=}"
            shift
            ;;
        --from-source)
            FROM_SOURCE=1
            shift
            ;;
        --install-rust)
            INSTALL_RUST=1
            shift
            ;;
        --no-ash)
            WITH_ASH=0
            shift
            ;;
        --no-modify-path)
            MODIFY_PATH=0
            shift
            ;;
        --uninstall)
            ACTION=uninstall
            shift
            ;;
        -q | --quiet)
            QUIET=1
            shift
            ;;
        -h | --help)
            ACTION=help
            shift
            ;;
        *)
            die "unknown option: $1 (see burnup help)"
            ;;
    esac
done

if [ "$ACTION" = help ]; then
    usage
    exit 0
fi

case "$PREFIX" in
    /*) ;;
    *) PREFIX="$(pwd)/$PREFIX" ;;
esac
BIN="$PREFIX/bin"
SHARE="$PREFIX/share/burn"
ENV_FILE="$PREFIX/env"
OWNED="$PREFIX/.burnup"
MARKER="# added by burnup"
OLD_MARKER="# added by the Burn installer"

need() {
    command -v "$1" >/dev/null 2>&1
}

profiles() {
    for f in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc" "$HOME/.zprofile"; do
        if [ -f "$f" ]; then
            printf '%s\n' "$f"
        fi
    done
}

remove_path_lines() {
    for f in $(profiles); do
        if grep -q -e "$MARKER" -e "$OLD_MARKER" "$f" 2>/dev/null; then
            tmp="$f.burnup-tmp"
            grep -v -e "$MARKER" -e "$OLD_MARKER" "$f" >"$tmp" || true
            cat "$tmp" >"$f"
            rm -f "$tmp"
        fi
    done
    rm -f "$HOME/.config/fish/conf.d/burn.fish"
}

if [ "$ACTION" = show ]; then
    [ -x "$BIN/burn" ] || die "Burn is not installed in $PREFIX"
    "$BIN/burn" version
    if [ -x "$BIN/ash" ]; then
        "$BIN/ash" version
    fi
    say "installed in $PREFIX"
    exit 0
fi

if [ "$ACTION" = uninstall ]; then
    if [ ! -x "$BIN/burn" ] && [ ! -d "$SHARE" ]; then
        die "no Burn installation found in $PREFIX"
    fi
    step "Removing $PREFIX"
    if [ -f "$OWNED" ]; then
        rm -rf "$PREFIX"
    else
        rm -f "$BIN/burn" "$BIN/burni" "$BIN/burnc" "$BIN/burnfmt" "$BIN/burn-lsp" "$BIN/bvm" "$BIN/ash" "$BIN/burnup"
        rm -rf "$SHARE" "$ENV_FILE" "$PREFIX/packages" "$PREFIX/tools" "$PREFIX/index" "$PREFIX/index.fetched"
        rmdir "$BIN" "$PREFIX/share" "$PREFIX" 2>/dev/null || true
    fi
    remove_path_lines
    say "${GREEN}Burn has been uninstalled.${RESET}"
    exit 0
fi

OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS" in
    Linux) OS_NAME=linux ;;
    Darwin) OS_NAME=macos ;;
    *) OS_NAME="$(printf '%s' "$OS" | tr '[:upper:]' '[:lower:]')" ;;
esac
case "$ARCH" in
    x86_64 | amd64) ARCH_NAME=x86_64 ;;
    arm64 | aarch64) ARCH_NAME=aarch64 ;;
    *) ARCH_NAME="$ARCH" ;;
esac

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t burnup)"
cleanup() {
    rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

download() {
    if need curl; then
        curl -fsSL "$1" -o "$2"
    elif need wget; then
        wget -q "$1" -O "$2"
    else
        return 1
    fi
}

clone() {
    if ! git clone --quiet --depth 1 --branch "$2" "$1" "$3" 2>/dev/null; then
        rm -rf "$3"
        git clone --quiet "$1" "$3" || return 1
        git -C "$3" checkout --quiet "$2" || return 1
    fi
}

install_release() {
    asset="burn-$OS_NAME-$ARCH_NAME.tar.gz"
    url="$BURN_REPO/releases/latest/download/$asset"
    if [ -n "${BURN_RELEASE_URL:-}" ]; then
        url="$BURN_RELEASE_URL"
    fi
    step "Looking for a prebuilt release ($asset)"
    if ! download "$url" "$WORK/$asset" 2>/dev/null; then
        say "    no prebuilt release available, building from source"
        return 1
    fi
    mkdir -p "$WORK/release"
    tar -xzf "$WORK/$asset" -C "$WORK/release" || return 1
    root="$WORK/release"
    if [ -d "$WORK/release/burn" ]; then
        root="$WORK/release/burn"
    fi
    [ -x "$root/bin/burn" ] || return 1
    mkdir -p "$BIN" "$SHARE"
    for exe in burn bvm burnfmt; do
        if [ -f "$root/bin/$exe" ] && [ ! -L "$root/bin/$exe" ]; then
            cp -f "$root/bin/$exe" "$BIN/$exe.new"
            mv -f "$BIN/$exe.new" "$BIN/$exe"
        fi
    done
    for tool in burni burnc burn-lsp; do
        rm -f "$BIN/$tool"
        ln -s burn "$BIN/$tool" 2>/dev/null || cp -f "$BIN/burn" "$BIN/$tool"
    done
    if [ -d "$root/share/burn" ]; then
        cp -R "$root/share/burn/." "$SHARE/"
    fi
    if [ ! -x "$BIN/burnfmt" ] || [ "$(head -c 2 "$BIN/burnfmt")" = "#!" ]; then
        return 1
    fi
    return 0
}

ensure_cargo() {
    if need cargo; then
        return 0
    fi
    if [ -x "$HOME/.cargo/bin/cargo" ]; then
        PATH="$HOME/.cargo/bin:$PATH"
        export PATH
        return 0
    fi
    if [ "$INSTALL_RUST" -eq 1 ]; then
        step "Installing Rust with rustup"
        download "https://sh.rustup.rs" "$WORK/rustup.sh" || die "could not download rustup"
        sh "$WORK/rustup.sh" -y --profile minimal >/dev/null || die "rustup failed"
        PATH="$HOME/.cargo/bin:$PATH"
        export PATH
        return 0
    fi
    die "cargo was not found. Install Rust from https://rustup.rs or rerun with --install-rust"
}

install_source() {
    ensure_cargo
    need git || die "git is required to download the Burn sources"
    step "Downloading Burn ($BURN_REF) from $BURN_REPO"
    clone "$BURN_REPO" "$BURN_REF" "$WORK/burn" || die "could not get $BURN_REF from $BURN_REPO"
    [ -f "$WORK/burn/scripts/package.sh" ] || die "$BURN_REF is too old for burnup (it has no scripts/package.sh)"
    step "Building Burn (this takes a minute the first time)"
    if [ "$QUIET" -eq 1 ]; then
        sh "$WORK/burn/scripts/package.sh" --prefix "$PREFIX" -q || die "the build failed"
    else
        sh "$WORK/burn/scripts/package.sh" --prefix "$PREFIX" || die "the build failed"
    fi
}

install_ash() {
    if ! need git; then
        warn "git is not installed, so ash was skipped (it needs git to download packages)"
        return 0
    fi
    step "Installing ash, the package manager"
    rm -rf "$WORK/ash"
    if ! clone "$ASH_REPO" "$ASH_REF" "$WORK/ash"; then
        warn "could not download ash from $ASH_REPO; install it later with: burnup update"
        return 0
    fi
    rm -rf "$SHARE/ash"
    mkdir -p "$SHARE"
    cp -R "$WORK/ash" "$SHARE/ash"
    rm -rf "$SHARE/ash/.git"
    if (cd "$SHARE/ash" && "$BIN/burn" build --target native -o "$BIN/ash.new" >/dev/null 2>"$WORK/ash.log"); then
        mv -f "$BIN/ash.new" "$BIN/ash"
        return 0
    fi
    rm -f "$BIN/ash.new"
    if grep -q -e "linker" -e "linking" -e "native" "$WORK/ash.log"; then
        warn "native compilation is not available here; ash will run on the interpreter"
        cat >"$BIN/ash" <<EOF
#!/bin/sh
exec "$BIN/burni" "$SHARE/ash/src/main.bn" "\$@"
EOF
        chmod +x "$BIN/ash"
        return 0
    fi
    cat "$WORK/ash.log" >&2
    die "ash does not build with this version of Burn"
}

install_self() {
    target="$BIN/burnup"
    if [ -f "$0" ] && grep -q "burnup - installs and updates the Burn toolchain" "$0" 2>/dev/null; then
        if [ "$0" != "$target" ]; then
            cp -f "$0" "$target.new"
            mv -f "$target.new" "$target"
        fi
    elif download "$BURNUP_URL" "$target.new" 2>/dev/null; then
        mv -f "$target.new" "$target"
    else
        rm -f "$target.new"
        warn "could not save burnup itself; update later by running the install command again"
        return 0
    fi
    chmod +x "$target"
}

write_env() {
    cat >"$ENV_FILE" <<EOF
case ":\${PATH}:" in
    *:"$BIN":*) ;;
    *) export PATH="$BIN:\$PATH" ;;
esac
EOF
}

modify_path() {
    write_env
    if [ "$MODIFY_PATH" -eq 0 ]; then
        return
    fi
    case ":$PATH:" in
        *":$BIN:"*) return ;;
    esac
    line=". \"$ENV_FILE\" $MARKER"
    updated=""
    for f in $(profiles); do
        if ! grep -q -e "$MARKER" -e "$OLD_MARKER" "$f" 2>/dev/null; then
            printf '\n%s\n' "$line" >>"$f"
        fi
        updated="$updated $f"
    done
    if [ -z "$updated" ]; then
        printf '%s\n' "$line" >>"$HOME/.profile"
        updated=" $HOME/.profile"
    fi
    if [ -d "$HOME/.config/fish" ]; then
        mkdir -p "$HOME/.config/fish/conf.d"
        printf 'fish_add_path -g "%s" %s\n' "$BIN" "$MARKER" >"$HOME/.config/fish/conf.d/burn.fish"
        updated="$updated $HOME/.config/fish/conf.d/burn.fish"
    fi
    say "    added $BIN to PATH in:$updated"
    PATH_CHANGED=1
}

fresh=0
if [ ! -e "$PREFIX" ]; then
    fresh=1
fi
if [ "$ACTION" = update ]; then
    say "${BOLD}Updating the Burn toolchain in $PREFIX${RESET}"
else
    say "${BOLD}Installing the Burn toolchain into $PREFIX${RESET}"
fi
mkdir -p "$BIN"
if [ "$fresh" -eq 1 ]; then
    : >"$OWNED"
fi
PATH_CHANGED=0

installed=0
if [ "$FROM_SOURCE" -eq 0 ] && install_release; then
    if "$BIN/burn" init --help >/dev/null 2>&1; then
        installed=1
    else
        say "    the latest release is older than burnup, building from source"
    fi
fi
if [ "$installed" -eq 0 ]; then
    install_source
fi
if [ "$WITH_ASH" -eq 1 ]; then
    install_ash
fi
install_self
modify_path

"$BIN/burn" version >/dev/null 2>&1 || die "the installed burn binary does not run"
check="$WORK/hello.bn"
printf 'print("ok")\n' >"$check"
[ "$("$BIN/burni" "$check")" = "ok" ] || die "burni could not run a test program"
[ "$(printf 'var  x=1\n' | "$BIN/burnfmt")" = "var x = 1" ] || die "burnfmt did not format a test program"
"$BIN/burnc" "$check" --target bvm -o "$WORK/hello.bvmc" >/dev/null || die "burnc could not compile a test program to bvm bytecode"
[ "$("$BIN/bvm" "$WORK/hello.bvmc")" = "ok" ] || die "bvm could not run a test program"
if [ -x "$BIN/ash" ]; then
    "$BIN/ash" version >/dev/null || die "the installed ash does not run"
fi

say ""
say "${GREEN}Burn $("$BIN/burn" version | sed 's/^Burn //') is installed.${RESET}"
say ""
say "  burn      run, build, check, fmt, init, repl, lsp"
say "  burni     interpreter and REPL"
say "  burnc     native, JavaScript and bvm bytecode compiler"
say "  burnfmt   code formatter"
say "  burn-lsp  language server for editors"
say "  bvm       the Burn virtual machine"
if [ -x "$BIN/ash" ]; then
    say "  ash       package manager: ash init github.com/you/app"
fi
say "  burnup    update or uninstall: burnup update, burnup uninstall"
say ""
if [ "$PATH_CHANGED" -eq 1 ]; then
    say "Restart your shell or run:  . \"$ENV_FILE\""
elif [ "$MODIFY_PATH" -eq 0 ]; then
    case ":$PATH:" in
        *":$BIN:"*) ;;
        *) say "Add $BIN to your PATH, for example:  . \"$ENV_FILE\"" ;;
    esac
fi
