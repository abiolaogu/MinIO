#!/bin/bash
# Universal Repository Transformation Kit Installer
#
# This script installs the transformation kit into any target repository.
# It accepts the target repository path as an argument and copies all
# necessary files without any hardcoded project references.
#
# Usage:
#   ./scripts/install_transformation_kit.sh [TARGET_REPO_PATH]
#
# Example:
#   ./scripts/install_transformation_kit.sh /path/to/my-project

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory (factory-template location)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
FACTORY_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# Parse arguments
TARGET_REPO="${1:-.}"
TARGET_REPO="$( cd "$TARGET_REPO" && pwd )"

echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Universal Repository Transformation Kit Installer${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}Source:${NC} $FACTORY_ROOT"
echo -e "${GREEN}Target:${NC} $TARGET_REPO"
echo ""

# Validate target
if [ ! -d "$TARGET_REPO/.git" ]; then
    echo -e "${RED}Error: Target is not a git repository${NC}"
    echo "Please provide a path to a valid git repository"
    exit 1
fi

# Create necessary directories
echo -e "${YELLOW}➤${NC} Creating directories..."
mkdir -p "$TARGET_REPO/.github/workflows"
mkdir -p "$TARGET_REPO/scripts/universal"
mkdir -p "$TARGET_REPO/templates/config"

# Copy universal scripts
echo -e "${YELLOW}➤${NC} Installing universal scripts..."
cp "$FACTORY_ROOT/scripts/universal/detect_tech_stack.py" "$TARGET_REPO/scripts/universal/"
cp "$FACTORY_ROOT/scripts/universal/universal_test.py" "$TARGET_REPO/scripts/universal/"
cp "$FACTORY_ROOT/scripts/universal/universal_build.py" "$TARGET_REPO/scripts/universal/"
cp "$FACTORY_ROOT/scripts/universal/universal_lint.py" "$TARGET_REPO/scripts/universal/"
cp "$FACTORY_ROOT/scripts/universal/README.md" "$TARGET_REPO/scripts/universal/"

# Make scripts executable
chmod +x "$TARGET_REPO/scripts/universal/"*.py

echo -e "${GREEN}  ✓${NC} Universal scripts installed"

# Copy workflow
echo -e "${YELLOW}➤${NC} Installing CI/CD workflow..."
cp "$FACTORY_ROOT/templates/workflows/universal-ci.yml" "$TARGET_REPO/.github/workflows/"
echo -e "${GREEN}  ✓${NC} Universal CI/CD workflow installed"

# Copy config template
echo -e "${YELLOW}➤${NC} Installing configuration template..."
cp "$FACTORY_ROOT/templates/config/universal-config-schema.yaml" "$TARGET_REPO/templates/config/"
echo -e "${GREEN}  ✓${NC} Configuration template installed"

# Copy documentation
echo -e "${YELLOW}➤${NC} Installing documentation..."
mkdir -p "$TARGET_REPO/docs"
cp "$FACTORY_ROOT/docs/universal-transformation-kit.md" "$TARGET_REPO/docs/"
echo -e "${GREEN}  ✓${NC} Documentation installed"

# Detect tech stack in target
echo ""
echo -e "${YELLOW}➤${NC} Detecting tech stack in target repository..."
cd "$TARGET_REPO"
python scripts/universal/detect_tech_stack.py > /tmp/tech_stack_detected.json
LANGUAGE=$(cat /tmp/tech_stack_detected.json | python -c "import sys, json; print(json.load(sys.stdin)['tech_stack']['primary_language'])")
FRAMEWORK=$(cat /tmp/tech_stack_detected.json | python -c "import sys, json; print(json.load(sys.stdin)['tech_stack']['framework'] or 'None')")

echo -e "${GREEN}  ✓${NC} Detected: $LANGUAGE" $([ "$FRAMEWORK" != "None" ] && echo "($FRAMEWORK)" || echo "")
echo ""
cat /tmp/tech_stack_detected.json | python -m json.tool

# Summary
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Installation Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""
echo "Installed components:"
echo "  • Universal scripts (scripts/universal/)"
echo "  • CI/CD workflow (.github/workflows/universal-ci.yml)"
echo "  • Configuration template (templates/config/universal-config-schema.yaml)"
echo "  • Documentation (docs/universal-transformation-kit.md)"
echo ""
echo "Next steps:"
echo "  1. Review the workflow: .github/workflows/universal-ci.yml"
echo "  2. Customize tier paths if needed"
echo "  3. Commit and push changes"
echo "  4. Open a PR to test the tier-based automation"
echo ""
echo "Read the docs: docs/universal-transformation-kit.md"
echo ""
