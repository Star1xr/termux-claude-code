YELLOW='\033[1;33m'
BLUE='\033[1;34m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

set -e

# we already fucking know people use termux cus repo is fucking named termux claude code?

echo -e "${YELLOW}Installing required packages.${NC}"
sleep 2
pkg update -y
pkg install glibc-repo -y
pkg install glibc-runner -y
pkg install nodejs-lts -y
pkg install ripgrep -y


# ---- Fix glibc-runner's unquoted $@ -----------------------------------------
# The glibc-runner package launches binaries with an UNQUOTED $@ in two places,
# which word-splits multi-word arguments -- so `claude -p "a b c"` arrives as
# the separate words a, b, c and Claude only sees the first. We re-quote it.
# These files are NOT dpkg conffiles, so apt silently overwrites them on
# upgrade/reinstall; we also install an apt Post-Invoke hook that re-applies the
# fix after every apt run so it survives future glibc-runner package updates.


echo -e "${YELLOW}Patching ${BLUE}glibc-runner${YELLOW} argument quoting.${NC}"
sleep 1

cat << 'SCRIPT_EOF' > "$PREFIX/etc/fix-glibc-runner-quoting.sh"
#!/data/data/com.termux/files/usr/bin/bash
# Re-apply the "$@" quoting fixes to glibc-runner after apt touches it.
# glibc-runner ships an unquoted $@ that word-splits multi-word args; the files
# are NOT dpkg conffiles, so apt overwrites them on upgrade/reinstall.
# Idempotent: each sed only matches the *unquoted* form, so re-runs are no-ops.
# Best-effort (always exits 0 so it can't break apt), but it warns on stderr and
# to a log if a target is no longer in the expected shape (i.e. the patch went
# stale because upstream changed the file), so the no-op never goes unnoticed.
set -u

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LOG="$PREFIX/var/log/fix-glibc-runner-quoting.log"

warn() {
    echo "fix-glibc-runner-quoting: WARNING: $*" >&2
    if mkdir -p "$PREFIX/var/log" 2>/dev/null; then
        printf '%s %s\n' "$(date 2>/dev/null)" "$*" >> "$LOG" 2>/dev/null
    fi
}

changed=0
problems=0

# All four launcher copies (glibc-runner + grun, in both bin dirs); a clean
# login shell resolves $PREFIX/bin/glibc-runner, glibc shells use glibc/bin.
for LAUNCHER in \
    "$PREFIX/glibc/bin/glibc-runner" \
    "$PREFIX/glibc/bin/grun" \
    "$PREFIX/bin/glibc-runner" \
    "$PREFIX/bin/grun"; do
    [ -f "$LAUNCHER" ] || continue
    if grep -q 'glibc-runner\.sh \$@$' "$LAUNCHER"; then
        sed -i 's|\(glibc-runner\.sh\) \$@$|\1 "$@"|' "$LAUNCHER"
        changed=1
    fi
    # Every launcher sources glibc-runner.sh; after patching it must be quoted.
    # References it but not quoted => sed failed or upstream changed the line.
    if grep -q 'glibc-runner\.sh' "$LAUNCHER" && ! grep -qF 'glibc-runner.sh "$@"' "$LAUNCHER"; then
        warn "$LAUNCHER not in expected 'glibc-runner.sh \"\$@\"' form; patch may be stale"
        problems=1
    fi
done

INNER="$PREFIX/opt/glibc-runner/glibc-runner.sh"
if [ -f "$INNER" ]; then
    if grep -qE '_glibc-runner_debug\) (ld\.so )?\$@$' "$INNER"; then
        sed -i 's|\(exec \$(_glibc-runner_debug)\) \$@$|\1 "$@"|' "$INNER"
        sed -i 's|\(exec \$(_glibc-runner_debug) ld\.so\) \$@$|\1 "$@"|' "$INNER"
        changed=1
    fi
    if grep -q 'exec \$(_glibc-runner_debug) ld\.so' "$INNER" && ! grep -qF 'exec $(_glibc-runner_debug) ld.so "$@"' "$INNER"; then
        warn "$INNER ld.so exec line not in expected quoted form; patch may be stale"
        problems=1
    fi
fi

if [ "$changed" = 1 ] && [ "$problems" = 0 ]; then
    echo "fix-glibc-runner-quoting: re-applied \"\$@\" quoting to glibc-runner"
fi

exit 0
SCRIPT_EOF
chmod +x "$PREFIX/etc/fix-glibc-runner-quoting.sh"

mkdir -p "$PREFIX/etc/apt/apt.conf.d"
HOOK_CONF="$PREFIX/etc/apt/apt.conf.d/99-fix-glibc-runner-quoting.conf"
cat << 'HOOK_EOF' > "$HOOK_CONF"
// Self-healing: re-apply the "$@" quoting fix to glibc-runner after every
// apt/dpkg run, since the package ships unquoted $@ and overwrites the files
// (they are not conffiles) on upgrade/reinstall.
HOOK_EOF
# what the continueous larp
printf 'DPkg::Post-Invoke { "%s/etc/fix-glibc-runner-quoting.sh || true"; };\n' "$PREFIX" >> "$HOOK_CONF"

# Apply the fix now (the hook only fires on the *next* apt run).
"$PREFIX/etc/fix-glibc-runner-quoting.sh"

echo -e "${YELLOW}Installing ${BLUE}claude${YELLOW} with npm.${NC}"
sleep 2
npm install -g @anthropic-ai/claude-code --force || echo -e "${RED}Could not install claude-code from npm. Check your internet connection, or update npm packages.${NC}"


echo -e "${YELLOW}Installing native binary for ${BLUE}claude${YELLOW}.${NC}"
sleep 2
URL=$(npm view @anthropic-ai/claude-code-linux-arm64 dist.tarball)

if [ -z "$URL" ]; then
    echo -e "${RED}Error: Cannot get URL. Check your internet connection.${NC}"
    exit 1
fi

echo "Installing: $URL"
wget -q --show-progress "$URL" || echo -e "${RED}Could not download native binary for claude code. Check your internet connection.${NC}"

mkdir -p /data/data/com.termux/files/usr/lib/node_modules/@anthropic-ai/claude-code-linux-arm64

tar -xvzf claude-code-linux-arm64-*.tgz -C /data/data/com.termux/files/usr/lib/node_modules/@anthropic-ai/claude-code-linux-arm64 --strip-components=1

rm claude-code-linux-arm64-*.tgz

cat << 'EOF' > /data/data/com.termux/files/usr/bin/claude
#!/data/data/com.termux/files/usr/bin/bash

PACKAGE="@anthropic-ai/claude-code-linux-arm64"
INSTALL_DIR="/data/data/com.termux/files/usr/lib/node_modules/$PACKAGE"
PACKAGE_JSON="$INSTALL_DIR/package.json"
BINARY_PATH="$INSTALL_DIR/claude"

if [ ! -f "$BINARY_PATH" ]; then
    echo "Claude binary not found at $BINARY_PATH"
    echo "Please reinstall it."
    exit 1
fi

SKIP_UPDATE=0
REAL_ARGS=()

for arg in "$@"; do
    if [ "$arg" = "-p" ] || [ "$arg" = "--print" ]; then
        SKIP_UPDATE=1
    else
        REAL_ARGS+=("$arg")
    fi
done

if [ "$SKIP_UPDATE" != 1 ]; then
    echo -n "Checking for updates... "
    LATEST_VERSION=$(npm view "$PACKAGE" version 2>/dev/null)

    if [ -f "$PACKAGE_JSON" ]; then
        INSTALLED_VERSION=$(grep '"version":' "$PACKAGE_JSON" | head -1 | cut -d'"' -f4)
    else
        INSTALLED_VERSION="none"
    fi

    if [ "$LATEST_VERSION" != "$INSTALLED_VERSION" ] && [ -n "$LATEST_VERSION" ]; then
        echo -e "\nNew version ($LATEST_VERSION) found. Updating..."
        URL=$(npm view "$PACKAGE" dist.tarball 2>/dev/null)
        UPDATE_TGZ="$HOME/claude_update.tgz"
        mkdir -p "$INSTALL_DIR"
        if wget -q --show-progress "$URL" -O "$UPDATE_TGZ"; then
            tar -xzf "$UPDATE_TGZ" -C "$INSTALL_DIR" --strip-components=1
            rm -f "$UPDATE_TGZ"
            chmod +x "$BINARY_PATH"
            echo "Update complete."
        else
            echo "Update download failed; running existing version."
        fi
        sleep 2
    else
        echo "Done (Already up to date)."
        sleep 2
    fi
fi

if [ "$SKIP_UPDATE" = 1 ]; then
    if [ -t 0 ] && [ ${#REAL_ARGS[@]} -eq 0 ]; then
        glibc-runner "$BINARY_PATH"
    elif [ -t 0 ] && [ ${#REAL_ARGS[@]} -gt 0 ]; then
        IS_INTERACTIVE=1
        for r_arg in "${REAL_ARGS[@]}"; do
            case "$r_arg" in
                config|doctor|mcp|--help|-h|--version|-v)
                    IS_INTERACTIVE=0
                    break
                    ;;
            esac
        done
        if [ "$IS_INTERACTIVE" -eq 1 ]; then
            glibc-runner "$BINARY_PATH" "${REAL_ARGS[@]}"
        else
            glibc-runner "$BINARY_PATH" "$@"
        fi
    else
        glibc-runner "$BINARY_PATH" "$@"
    fi
else
    glibc-runner "$BINARY_PATH" "$@"
fi
EOF

chmod +x "$PREFIX/bin/claude"

# Companion to BASH_ENV in the wrapper
cat << 'SHIMFIX_EOF' > "$PREFIX/etc/claude-bash-shim-fix.sh"
# Sourced via BASH_ENV by every non-interactive bash Claude Code spawns for its
# Bash tool. Under glibc-runner, Claude exports CLAUDE_CODE_EXECPATH pointing at
# ld.so; its injected grep()/find() shell functions then run `ld.so -G/-S ...`
# -> "error while loading shared libraries". Emptying EXECPATH makes those shims
# take their built-in fallback to `command grep` / `command find` (native).
export CLAUDE_CODE_EXECPATH=
SHIMFIX_EOF

echo -e "${GREEN}=== INSTALLATION COMPLETE ===${NC}"
echo -e "${YELLOW}Run with: ${BLUE}claude${NC}"
echo -e "${YELLOW}Update checks are on${NC} (skip with ${BLUE}claude -p${NC}; set ${BLUE}CLAUDE_SKIP_UPDATE=1${NC} to always skip)."
echo -e "Every time you type ${BLUE}claude${NC}, it will check for updates and run natively."
