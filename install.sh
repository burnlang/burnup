#!/bin/sh
set -eu

BURN_REPO="${BURN_REPO:-https://github.com/burnlang/burn}"
BURN_REF="${BURN_REF:-master}"
BURN_RELEASES="${BURN_RELEASES:-$BURN_REPO/releases/download}"
BURNUP_REPO="${BURNUP_REPO:-https://github.com/burnlang/burnup}"
BURNUP_REF="${BURNUP_REF:-master}"
BURNUP_RELEASES="${BURNUP_RELEASES:-https://github.com/burnlang/burnup/releases/latest/download}"
PREFIX="${BURN_HOME:-$HOME/.burn}"
FROM_SOURCE=0
INSTALL_RUST=0
TOOLCHAIN=""
NO_ASH=0
NO_PATH=0

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD="$(printf '\033[1m')"
    RED="$(printf '\033[31m')"
    RESET="$(printf '\033[0m')"
else
    BOLD=""
    RED=""
    RESET=""
fi

step() {
    printf '%s\n' "${BOLD}==>${RESET} $*" >&2
}

die() {
    printf '%s\n' "${RED}error:${RESET} $*" >&2
    exit 1
}

usage() {
    cat <<EOF
Installs burnup, the Burn version manager, and with it the newest Burn and ash.

Usage:
  curl -fsSL https://raw.githubusercontent.com/burnlang/burnup/master/install.sh | sh
  curl -fsSL https://raw.githubusercontent.com/burnlang/burnup/master/install.sh | sh -s -- [options]

Options:
  --prefix <dir>        install into <dir> instead of ~/.burn
  --toolchain <version> the Burn version to install first (default: the latest)
  --from-source         build Burn and burnup from source instead of downloading them
  --install-rust        install Rust with rustup if a source build needs it
  --no-ash              do not install ash, the package manager
  --no-modify-path      do not add ~/.burn/bin to your shell profile
  -h, --help            show this help

Afterwards, burnup manages everything: burnup help
EOF
}

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
        --toolchain)
            [ $# -ge 2 ] || die "--toolchain needs a version"
            TOOLCHAIN="$2"
            shift 2
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
            NO_ASH=1
            shift
            ;;
        --no-modify-path)
            NO_PATH=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1 (see --help)"
            ;;
    esac
done

case "$PREFIX" in
    /*) ;;
    *) PREFIX="$(pwd)/$PREFIX" ;;
esac
BIN="$PREFIX/bin"
export BURN_HOME="$PREFIX" BURN_REPO

need() {
    command -v "$1" >/dev/null 2>&1
}

download() {
    if need curl; then
        curl -fsSL "$1" -o "$2"
    elif need wget; then
        wget -q "$1" -O "$2"
    else
        return 1
    fi
}

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$OS" in darwin) OS=macos ;; esac
case "$ARCH" in amd64) ARCH=x86_64 ;; arm64) ARCH=aarch64 ;; esac

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t burnup)"
trap 'rm -rf "$WORK"' EXIT INT TERM
mkdir -p "$BIN"
if [ ! -e "$PREFIX/.burnup" ] && [ -z "$(ls -A "$BIN" 2>/dev/null)" ]; then
    : >"$PREFIX/.burnup"
fi

prebuilt() {
    [ "$FROM_SOURCE" -eq 0 ] || return 1
    step "Downloading burnup for $OS-$ARCH"
    download "$BURNUP_RELEASES/burnup-$OS-$ARCH" "$WORK/burnup" 2>/dev/null || return 1
    chmod +x "$WORK/burnup"
    "$WORK/burnup" version >/dev/null 2>&1 || return 1
    mv -f "$WORK/burnup" "$BIN/burnup"
}

ensure_cargo() {
    need cargo && return 0
    if [ -x "$HOME/.cargo/bin/cargo" ]; then
        PATH="$HOME/.cargo/bin:$PATH"
        export PATH
        return 0
    fi
    [ "$INSTALL_RUST" -eq 1 ] || die "building Burn needs Rust, but cargo was not found. Install it from https://rustup.rs or rerun with --install-rust"
    step "Installing Rust with rustup"
    download "https://sh.rustup.rs" "$WORK/rustup.sh" || die "could not download rustup"
    sh "$WORK/rustup.sh" -y --profile minimal >/dev/null || die "rustup failed"
    PATH="$HOME/.cargo/bin:$PATH"
    export PATH
}

clone() {
    if ! git clone --quiet --depth 1 --branch "$2" "$1" "$3" 2>/dev/null; then
        rm -rf "$3"
        git clone --quiet "$1" "$3" || return 1
        git -C "$3" checkout --quiet "$2" || return 1
    fi
}

from_source() {
    need git || die "git is needed to download Burn"
    ensure_cargo
    name="$(printf '%s' "$BURN_REF" | tr '/' '-')"
    toolchain="$PREFIX/toolchains/$name"
    if [ ! -x "$toolchain/bin/burn" ]; then
        step "Downloading Burn ($BURN_REF)"
        clone "$BURN_REPO" "$BURN_REF" "$WORK/burn" || die "could not get $BURN_REF from $BURN_REPO"
        [ -f "$WORK/burn/scripts/package.sh" ] || die "Burn $BURN_REF is too old for burnup"
        set --
        if [ -f "$WORK/burn/compiler/STAGE0" ]; then
            stage0="$(tr -d ' \n' <"$WORK/burn/compiler/STAGE0")"
            step "Downloading Burn $stage0, which builds Burn for the first time"
            download "$BURN_RELEASES/$stage0/burn-$OS-$ARCH.tar.gz" "$WORK/stage0.tar.gz" || die "could not download Burn $stage0 for $OS-$ARCH"
            mkdir -p "$WORK/stage0"
            tar -xzf "$WORK/stage0.tar.gz" -C "$WORK/stage0" || die "could not unpack Burn $stage0"
            set -- --stage0 "$WORK/stage0/burn/bin/burn"
        fi
        step "Building Burn (this takes a minute)"
        rm -rf "$toolchain.partial"
        sh "$WORK/burn/scripts/package.sh" --prefix "$toolchain.partial" -q "$@" || die "the Burn build failed"
        rm -rf "$toolchain"
        mv "$toolchain.partial" "$toolchain"
        version="$("$toolchain/bin/burn" version | sed 's/^Burn //')"
        rev="$(git -C "$WORK/burn" rev-parse HEAD)"
        printf 'name = "%s"\nref = "%s"\nrev = "%s"\nsource = "source"\nversion = "%s"\n' "$name" "$BURN_REF" "$rev" "$version" >"$toolchain/burnup.toml"
    fi
    step "Building burnup"
    rm -rf "$WORK/burnup-src"
    clone "$BURNUP_REPO" "$BURNUP_REF" "$WORK/burnup-src" || die "could not get burnup from $BURNUP_REPO"
    if (cd "$WORK/burnup-src" && "$toolchain/bin/burn" build --target native -o "$BIN/burnup.new" >/dev/null 2>"$WORK/burnup.log"); then
        mv -f "$BIN/burnup.new" "$BIN/burnup"
    else
        grep -q -e native -e link "$WORK/burnup.log" || { cat "$WORK/burnup.log" >&2; die "burnup does not build"; }
        rm -rf "$PREFIX/share/burnup"
        mkdir -p "$PREFIX/share"
        cp -R "$WORK/burnup-src" "$PREFIX/share/burnup"
        printf '#!/bin/sh\nexec "%s" "%s" "$@"\n' "$toolchain/bin/burni" "$PREFIX/share/burnup/src/main.bn" >"$BIN/burnup"
        chmod +x "$BIN/burnup"
    fi
    if [ -z "$TOOLCHAIN" ]; then
        TOOLCHAIN="$name"
    fi
}

if ! prebuilt; then
    from_source
fi

set -- setup
if [ -n "$TOOLCHAIN" ]; then
    set -- "$@" --toolchain "$TOOLCHAIN"
fi
if [ "$NO_ASH" -eq 1 ]; then
    set -- "$@" --no-ash
fi
if [ "$NO_PATH" -eq 1 ]; then
    set -- "$@" --no-modify-path
fi
step "Setting up"
exec "$BIN/burnup" "$@"
