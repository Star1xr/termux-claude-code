YELLOW='\033[1;33m'
BLUE='\033[1;34m'
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

set -e

echo -e "${YELLOW}Installing required packages.${NC}"
sleep 0.5
pkg update -y
pkg install glibc-repo -y
pkg install glibc-runner -y
pkg install nodejs-lts -y

echo -e "${YELLOW}Installing ${BLUE}claude${YELLOW} with npm.${NC}"
sleep 0.5
npm install -g @anthropic-ai/claude-code --force || echo -e "${RED}Could not install claude-code from npm. Check your internet connection, or update npm packages.${NC}"


echo -e "${YELLOW}Installing native binary for ${BLUE}claude${YELLOW}.${NC}"
sleep 0.5
URL=$(npm view @anthropic-ai/claude-code-linux-arm64 dist.tarball)

if [ -z "$URL" ]; then
    echo "${RED}Error: Cannot get URL. Check your internet connection.${NC}"
    exit 1
fi

echo "Installing: $URL"
wget -q --show-progress "$URL" || echo -e "${RED}Could not download native binary for claude code. Check your internet connection.${NC}"

mkdir -p /data/data/com.termux/files/usr/lib/node_modules/@anthropic-ai/claude-code-linux-arm64

tar -xvzf claude-code-linux-arm64-*.tgz -C /data/data/com.termux/files/usr/lib/node_modules/@anthropic-ai/claude-code-linux-arm64 --strip-components=1 

rm claude-code-linux-arm64-*.tgz

cat << 'EOF' > $PREFIX/bin/claude
#!/bin/bash

PACKAGE="@anthropic-ai/claude-code-linux-arm64"
INSTALL_DIR="/data/data/com.termux/files/usr/lib/node_modules/$PACKAGE"
PACKAGE_JSON="$INSTALL_DIR/package.json"
BINARY_PATH="$INSTALL_DIR/claude"

# 1. Güncelleme Kontrolü
if [ ! -f "$BINARY_PATH" ]; then
    echo "Claude binary not found at $BINARY_PATH"
    echo "Please reinstall it."
    exit 1
fi
echo -n "Checking for updates... "
LATEST_VERSION=$(npm view $PACKAGE version 2>/dev/null)

if [ -f "$PACKAGE_JSON" ]; then
    INSTALLED_VERSION=$(grep '"version":' "$PACKAGE_JSON" | cut -d'"' -f4)
else
    INSTALLED_VERSION="none"
fi

if [ "$LATEST_VERSION" != "$INSTALLED_VERSION" ] && [ ! -z "$LATEST_VERSION" ]; then
    echo -e "\n New version ($LATEST_VERSION) found. Updating..."
    URL=$(npm view $PACKAGE dist.tarball)
    mkdir -p "$INSTALL_DIR"
    TARBALL="$HOME/claude_update.tgz"
    wget -q --show-progress "$URL" -O "$TARBALL"
    tar -xzf "$TARBALL" -C "$INSTALL_DIR" --strip-components=1
    rm "$TARBALL"
    chmod +x "$BINARY_PATH"
    echo "Update complete."
    sleep 0.5
else
    echo "Done (Already up to date)."
    sleep 0.5
fi

glibc-runner /data/data/com.termux/files/usr/lib/node_modules/@anthropic-ai/claude-code-linux-arm64/claude
EOF
echo -e "${YELLOW}Run with: ${BLUE}claude${NC}"
echo -e "${YELLOW}Update checks are on.${NC}"

echo -e "${GREEN}=== INSTALLATION COMPLETE ===${NC}"
echo -e "Now, every time you type ${BLUE}claude${NC}, it will check for updates and run natively."
