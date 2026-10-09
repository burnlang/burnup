#!/bin/sh
set -eu

here="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap '[ -n "${KEEP:-}" ] || rm -rf "$work"' EXIT
export HOME="$work/home" BURN_HOME="$work/home/.burn" NO_COLOR=1 ASH_REPO="$work/no-ash"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
mkdir -p "$HOME"
touch "$HOME/.profile"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

expect() {
    printf '%s' "$1" | grep -q -- "$2" || fail "expected \"$2\" in: $1"
}

burn_exe="$(command -v burn)"
burni_exe="$(command -v burni)"
burn_root="$(cd "$(dirname "$burn_exe")/.." && pwd)"
dist="$work/dist/burn"
mkdir -p "$work/dist"
cp -R "$burn_root" "$dist"
rm -f "$dist/burnup.toml"

platform="$(uname -s | tr '[:upper:]' '[:lower:]' | sed 's/darwin/macos/')-$(uname -m | sed 's/amd64/x86_64/; s/arm64/aarch64/')"
repo="$work/burn-repo"
git init -q "$repo"
for tag in v1.0.0 v1.1.0 v2.0.0-beta; do
    printf '%s\n' "$tag" >"$repo/VERSION"
    git -C "$repo" add -A
    git -C "$repo" commit -q -m "$tag"
    git -C "$repo" tag "$tag"
    mkdir -p "$work/releases/$tag"
    tar -czf "$work/releases/$tag/burn-$platform.tar.gz" -C "$work/dist" burn
done
export BURN_REPO="$repo" BURN_RELEASES="file://$work/releases"

mkdir -p "$BURN_HOME/bin"
BURNUP="$BURN_HOME/bin/burnup"
if [ -n "${BURNUP_BIN:-}" ]; then
    cp "$BURNUP_BIN" "$BURNUP"
else
    printf '#!/bin/sh\nexec %s %s "$@"\n' "$burni_exe" "$here/src/main.bn" >"$BURNUP"
    chmod +x "$BURNUP"
fi

out="$($BURNUP setup --no-ash 2>&1)"
expect "$out" "Installed Burn v1.1.0"
expect "$out" "is installed"
grep -q "added by burnup" "$HOME/.profile" || fail "setup did not add burn to PATH"
export PATH="$BURN_HOME/bin:$PATH"

[ "$(burn eval 'print(6 * 7)')" = "42" ] || fail "the burn shim did not run"
[ "$(printf 'print("hi")\n' >"$work/hi.bn"; burni "$work/hi.bn")" = "hi" ] || fail "the burni shim did not run"
[ "$($BURNUP default)" = "v1.1.0" ] || fail "latest should be the newest stable release"

out="$($BURNUP install 1.0 2>&1)"
expect "$out" "Installed Burn v1.0.0"
out="$($BURNUP list)"
expect "$out" "v1.0.0"
expect "$out" "v1.1.0.*(default)"

$BURNUP default 1.0 >/dev/null 2>&1
[ "$($BURNUP default)" = "v1.0.0" ] || fail "default did not switch"
expect "$($BURNUP which burnc)" "toolchains/v1.0.0/bin/burnc"

cd "$work"
burn init example.com/test/proj --no-git >/dev/null
cd proj
$BURNUP pin 1.1 >/dev/null 2>&1
grep -q '^burn = "1.1"$' burn.toml || fail "pin did not write burn.toml: $(cat burn.toml)"
expect "$($BURNUP which)" "toolchains/v1.1.0/bin/burn"
expect "$($BURNUP show)" "from $work/proj/burn.toml"
[ "$(burn run)" = "Hello from proj!" ] || fail "the project did not run with its pinned version"
cd src
expect "$($BURNUP which)" "toolchains/v1.1.0/bin/burn"
cd "$work"
expect "$($BURNUP which)" "toolchains/v1.0.0/bin/burn"

mkdir -p "$work/other"
cd "$work/other"
$BURNUP pin 1.0.0 >/dev/null 2>&1
[ "$(cat .burn-version)" = "1.0.0" ] || fail "pin outside a project should write .burn-version"
cd "$work"

[ "$(BURN_TOOLCHAIN=v1.1.0 $BURNUP which)" = "$BURN_HOME/toolchains/v1.1.0/bin/burn" ] || fail "BURN_TOOLCHAIN was ignored"
expect "$($BURNUP run v1.1.0 burn version)" "Burn "

$BURNUP uninstall v1.1.0 >/dev/null 2>&1
[ ! -e "$BURN_HOME/toolchains/v1.1.0" ] || fail "uninstall left the toolchain"
cd "$work/proj"
out="$(burn lsp </dev/null 2>&1 || true)"
expect "$out" "the language server uses v1.0.0"
[ ! -e "$BURN_HOME/toolchains/v1.1.0" ] || fail "starting the language server installed a toolchain"
date +%s000 >"$BURN_HOME/toolchains/.v1.1.0.lock"
if burn run >/dev/null 2>"$work/err"; then fail "a held install lock was ignored"; fi
expect "$(cat "$work/err")" "another burnup is installing Burn v1.1.0"
rm -f "$BURN_HOME/toolchains/.v1.1.0.lock"
out="$(burn run 2>&1)"
expect "$out" "Missing Burn 1.1"
expect "$out" "Hello from proj!"
cd "$work"

if $BURNUP install 9.9 2>"$work/err"; then fail "a missing version was accepted"; fi
expect "$(cat "$work/err")" "there is no Burn version called"
expect "$(cat "$work/err")" "v1.1.0"
expect "$($BURNUP list --remote)" "v2.0.0-beta"

if $BURNUP link loop "$BURN_HOME" 2>"$work/err"; then fail "linking the burnup home was accepted"; fi
expect "$(cat "$work/err")" "is a burnup shim"
$BURNUP link dev "$dist" >/dev/null 2>&1
expect "$($BURNUP list)" "dev"
[ "$($BURNUP run dev burn eval 'print(1)')" = "1" ] || fail "the linked version did not run"

$BURNUP self uninstall >/dev/null 2>&1
[ ! -e "$BURN_HOME" ] || fail "self uninstall left $BURN_HOME"
if grep -q "added by burnup" "$HOME/.profile"; then fail "self uninstall left the PATH line"; fi

printf 'burnup end-to-end tests passed\n'
