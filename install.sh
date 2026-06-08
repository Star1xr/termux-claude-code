YELLOW='\033[1;33m'
BLUE='\033[1;34m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

set -e

echo -e "${YELLOW}Installing required packages.${NC}"
sleep 2
pkg update -y
pkg install glibc-repo -y
pkg install glibc-runner -y
pkg install nodejs-lts -y
# ripgrep: Claude Code uses it for search. We point Claude Code at the system
# rg (see USE_BUILTIN_RIPGREP below), because the binary's bundled ripgrep is a
# glibc binary launched via ld.so and fails to load standalone on this setup.
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
# Idempotent: each sed only matches the *unquoted* form, so re-runs are no-ops.
set -u
LAUNCHER="/data/data/com.termux/files/usr/glibc/bin/glibc-runner"
INNER="/data/data/com.termux/files/usr/opt/glibc-runner/glibc-runner.sh"
changed=0
if [ -f "$LAUNCHER" ]; then
    if grep -q 'glibc-runner\.sh \$@$' "$LAUNCHER"; then
        sed -i 's|\(glibc-runner\.sh\) \$@$|\1 "$@"|' "$LAUNCHER"
        changed=1
    fi
fi
if [ -f "$INNER" ]; then
    if grep -qE '_glibc-runner_debug\) (ld\.so )?\$@$' "$INNER"; then
        sed -i 's|\(exec \$(_glibc-runner_debug)\) \$@$|\1 "$@"|' "$INNER"
        sed -i 's|\(exec \$(_glibc-runner_debug) ld\.so\) \$@$|\1 "$@"|' "$INNER"
        changed=1
    fi
fi
if [ "$changed" = 1 ]; then
    echo "fix-glibc-runner-quoting: re-applied \"\$@\" quoting to glibc-runner"
fi
exit 0
SCRIPT_EOF
chmod +x "$PREFIX/etc/fix-glibc-runner-quoting.sh"

mkdir -p "$PREFIX/etc/apt/apt.conf.d"
cat << 'HOOK_EOF' > "$PREFIX/etc/apt/apt.conf.d/99-fix-glibc-runner-quoting.conf"
// Self-healing: re-apply the "$@" quoting fix to glibc-runner after every
// apt/dpkg run, since the package ships unquoted $@ and overwrites the files
// (they are not conffiles) on upgrade/reinstall.
DPkg::Post-Invoke { "/data/data/com.termux/files/usr/etc/fix-glibc-runner-quoting.sh || true"; };
HOOK_EOF

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

cat << 'EOF' > $PREFIX/bin/claude
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

# Skip the update check in non-interactive print mode (-p/--print): it adds
# network latency and its "Checking for updates..." text prints to stdout,
# which corrupts -p output (especially --output-format json).
# Set CLAUDE_SKIP_UPDATE=1 to skip the check always.
SKIP_UPDATE="${CLAUDE_SKIP_UPDATE:-0}"
for a in "$@"; do
    case "$a" in
        -p|--print) SKIP_UPDATE=1; break;;
    esac
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

# Use the system ripgrep (/usr/bin/rg). The binary's bundled ripgrep is a glibc
# binary launched via ld.so, so Claude Code's grep() shell integration would run
# `ld.so -G ...` -> "-G: error while loading shared libraries". System rg loads
# fine and restores the native Grep tool.
export USE_BUILTIN_RIPGREP=0

# exec + "$@": replace this process AND forward all arguments to claude.
exec glibc-runner "$BINARY_PATH" "$@"
EOF

chmod +x $PREFIX/bin/claude

echo -e "${GREEN}=== INSTALLATION COMPLETE ===${NC}"
echo -e "${YELLOW}Run with: ${BLUE}claude${NC}"
echo -e "${YELLOW}Update checks run on interactive launch${NC} (skipped for ${BLUE}claude -p${NC}; set ${BLUE}CLAUDE_SKIP_UPDATE=1${NC} to always skip)."
echo -e "Every time you type ${BLUE}claude${NC} interactively, it will check for updates and run natively."
