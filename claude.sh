#!/data/data/com.termux/files/usr/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${BLUE}=== Claude Code Termux Native Installer ===${NC}"
echo -e "${BLUE}=== Auto-Update Enabled | No Proot ===${NC}"

# 1. Setup Environment
echo -e "${GREEN}[1/2] Installing Glibc environment...${NC}"
pkg update -y
pkg install glibc-repo -y
pkg install nodejs-lts -y
pkg install glibc-runner -y 

# 2. Initial Install
echo -e "${GREEN}[2/2] Installing Claude Code...${NC}"
npm install -g @anthropic-ai/claude-code --force

# 3. Create the Auto-Update Function
# We replace the alias with a function in .bashrc
CLAUDE_BIN_PATH="$PREFIX/lib/node_modules/@anthropic-ai/claude-code-linux-arm64/bin/package/claude"

cat << 'EOF' >> ~/.bashrc

# Claude Code Native Function with Auto-Update
claude() {
    echo -e "\033[0;33mChecking for Claude Code updates...\033[0m"
    # Update silently in the background
    npm install -g @anthropic-ai/claude-code --force --silent
    
    CLAUDE_PATH="$PREFIX/lib/node_modules/@anthropic-ai/claude-code-linux-arm64/bin/package/claude"
    if [ -f "$CLAUDE_PATH" ]; then
        chmod +x "$CLAUDE_PATH"
        glibc-runner "$CLAUDE_PATH" "$@"
    else
        echo -e "\033[0;31mError: Claude binary not found. Try reinstalling.\033[0m"
    fi
}
EOF

echo -e "${GREEN}=== INSTALLATION COMPLETE ===${NC}"
echo -e "Run: ${BLUE}source ~/.bashrc${NC} to activate."
echo -e "Now, every time you type ${BLUE}claude${NC}, it will check for updates and run natively."
