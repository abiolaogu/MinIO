#!/bin/bash
# Quick installer script for VoxGuard repository
# This script wraps the Python installation script with pre-configured target

set -e

# Color output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check for FACTORY_ADMIN_TOKEN
if [ -z "$FACTORY_ADMIN_TOKEN" ]; then
    echo -e "${RED}ERROR: FACTORY_ADMIN_TOKEN environment variable not set${NC}"
    echo ""
    echo "Please export your GitHub Personal Access Token:"
    echo "  export FACTORY_ADMIN_TOKEN=\"your_token_here\""
    echo ""
    echo "Create a token at: https://github.com/settings/tokens"
    echo "Required scopes: 'repo' and 'workflow'"
    exit 1
fi

# Target repository
TARGET_REPO="https://github.com/abiolaogu/VoxGuard"

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo -e "${YELLOW}Installing Factory to VoxGuard...${NC}"
echo ""

# Execute Python installation script
python3 "$SCRIPT_DIR/install_remote.py" "$TARGET_REPO"

exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Factory successfully installed to VoxGuard!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Visit: $TARGET_REPO"
    echo "  2. Configure secrets (ANTHROPIC_API_KEY, FACTORY_ADMIN_TOKEN)"
    echo "  3. Factory will begin automatic assessment"
else
    echo ""
    echo -e "${RED}❌ Installation failed with exit code $exit_code${NC}"
    exit $exit_code
fi
