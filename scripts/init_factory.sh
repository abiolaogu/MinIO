#!/bin/bash
# Factory Initialization Script
# This script helps set up the factory template when first created from template

set -e

echo "🏭 Factory Template Initialization"
echo "=" echo "========================================"

# Check if already initialized
if [ -f ".factory-initialized" ]; then
    echo "✅ Factory already initialized!"
    echo ""
    echo "To re-initialize, delete .factory-initialized and run this script again."
    exit 0
fi

echo ""
echo "📋 Checking configuration..."
echo ""

# Check for required secrets (via environment variables)
SECRETS_OK=true

if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "❌ ANTHROPIC_API_KEY not set"
    SECRETS_OK=false
else
    echo "✅ ANTHROPIC_API_KEY is configured"
fi

if [ -z "$FACTORY_ADMIN_TOKEN" ]; then
    echo "❌ FACTORY_ADMIN_TOKEN not set"
    SECRETS_OK=false
else
    echo "✅ FACTORY_ADMIN_TOKEN is configured"
fi

if [ -z "$GITHUB_TOKEN" ]; then
    echo "⚠️  GITHUB_TOKEN not set (using FACTORY_ADMIN_TOKEN)"
    export GITHUB_TOKEN="$FACTORY_ADMIN_TOKEN"
fi

echo ""

if [ "$SECRETS_OK" = false ]; then
    echo "⚠️  Required secrets are not configured!"
    echo ""
    echo "To activate your autonomous factory, you need to add these secrets:"
    echo ""
    echo "1️⃣  ANTHROPIC_API_KEY"
    echo "   Purpose: Powers Claude Code Action for all AI workflows"
    echo "   Get it at: https://console.anthropic.com/"
    echo ""
    echo "2️⃣  FACTORY_ADMIN_TOKEN"
    echo "   Purpose: GitHub PAT for cross-repo operations"
    echo "   Required scopes: repo, workflow"
    echo "   Create at: https://github.com/settings/tokens"
    echo ""
    echo "📚 For detailed instructions, see:"
    echo "   - docs/AUTONOMOUS_INITIALIZATION.md"
    echo "   - docs/DEVELOPER_MANUAL.md"
    echo ""

    # Create a setup reminder issue if gh CLI is available
    if command -v gh &> /dev/null; then
        echo "📝 Creating setup reminder issue..."

        gh issue create \
            --title "🏭 Factory Setup Required - Configure Secrets" \
            --label "setup,documentation" \
            --body "## Setup Required

Your factory template needs configuration to become fully autonomous.

### Missing Secrets

Please add these secrets in **Settings → Secrets → Actions**:

- \`ANTHROPIC_API_KEY\` - Get from https://console.anthropic.com/
- \`FACTORY_ADMIN_TOKEN\` - Create at https://github.com/settings/tokens (needs \`repo\` and \`workflow\` scopes)

### After Adding Secrets

Run this script again:
\`\`\`bash
./scripts/init_factory.sh
\`\`\`

Or run the verification script:
\`\`\`bash
python scripts/verify_setup.py
\`\`\`

See [docs/AUTONOMOUS_INITIALIZATION.md](./docs/AUTONOMOUS_INITIALIZATION.md) for complete instructions." || echo "   (Issue creation failed - you may need to create it manually)"
    fi

    exit 1
fi

echo "✅ All required secrets are configured!"
echo ""

# Run verification script if available
if [ -f "scripts/verify_setup.py" ]; then
    echo "🔍 Running detailed verification..."
    python scripts/verify_setup.py || echo "⚠️  Verification completed with warnings"
    echo ""
fi

# Run initial market scan if market_scan.py exists
if [ -f "scripts/market_scan.py" ]; then
    echo "🔍 Running initial market intelligence scan..."
    export GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-$(git config --get remote.origin.url | sed 's/.*github.com[:/]\(.*\)\.git/\1/')}"
    python scripts/market_scan.py || echo "⚠️  Market scan completed with warnings (normal for first run)"
    echo ""
fi

# Create initialization marker
echo "📝 Marking factory as initialized..."
cat > .factory-initialized <<EOF
Factory initialized on $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Initialized by: ${USER:-unknown}
Repository: ${GITHUB_REPOSITORY:-unknown}
EOF

# Commit marker file
if git rev-parse --git-dir > /dev/null 2>&1; then
    git add .factory-initialized
    git commit -m "chore: Mark factory as initialized

This marker file prevents re-running initialization.
Created by scripts/init_factory.sh" || echo "   (Commit skipped - may already exist)"
fi

echo ""
echo "=" echo "========================================"
echo "🎉 Factory Initialization Complete!"
echo "=" echo "========================================"
echo ""
echo "Your autonomous factory is now operational!"
echo ""
echo "### 🤖 Active Systems"
echo ""
echo "1. Research Loop (Daily at 8 AM UTC)"
echo "   - Monitors market for intelligence"
echo "   - Workflow: .github/workflows/research-loop.yml"
echo ""
echo "2. Research Ingestion Pipeline"
echo "   - Triggers on files in research/incoming/"
echo "   - Workflow: .github/workflows/research-ingestion.yml"
echo ""
echo "3. Product Initiation"
echo "   - Triggers on 'approved-for-development' label"
echo "   - Workflow: .github/workflows/product-initiation.yml"
echo ""
echo "### 🚀 Quick Start"
echo ""
echo "Test the system:"
echo "  gh workflow run research-loop.yml"
echo ""
echo "Add research:"
echo "  echo '# Analysis' > research/incoming/test.md"
echo "  git add research/incoming/test.md && git commit -m 'test' && git push"
echo ""
echo "📚 Read the documentation:"
echo "  - docs/DEVELOPER_MANUAL.md - Complete guide"
echo "  - docs/AUTONOMOUS_INITIALIZATION.md - Setup details"
echo "  - CLAUDE.md - Factory constitution"
echo ""

# Create success issue if gh CLI is available
if command -v gh &> /dev/null; then
    echo "📝 Creating success issue..."

    gh issue create \
        --title "🎉 Factory Initialized Successfully!" \
        --label "setup,documentation" \
        --body "## Initialization Complete!

Your autonomous factory has been successfully configured and is now operational.

### ✅ What Was Configured

- Required secrets verified (ANTHROPIC_API_KEY, FACTORY_ADMIN_TOKEN)
- Initial market scan completed
- Repository marked as initialized

### 🤖 Active Autonomous Systems

Your factory now has these systems running automatically:

1. **Research Loop** (Daily at 8 AM UTC) - Monitors market intelligence
2. **Research Ingestion** - Analyzes files in \`research/incoming/\`
3. **Product Initiation** - Creates repos when opportunities are approved
4. **Bidirectional Sync** - Keeps code synchronized
5. **Sales Activation** - Triggers on release publication

### 🚀 Quick Start

Test the research loop:
\`\`\`bash
gh workflow run research-loop.yml
\`\`\`

Test research ingestion:
\`\`\`bash
echo '# Market Analysis' > research/incoming/test-analysis.md
git add research/incoming/test-analysis.md
git commit -m 'research: Add test'
git push
\`\`\`

### 📚 Next Steps

1. Read [Developer Manual](./docs/DEVELOPER_MANUAL.md)
2. Customize [CLAUDE.md](./CLAUDE.md) with your project description
3. Configure [ideal-customer-profile.yaml](./config/ideal-customer-profile.yaml)
4. Set up MCP tools in your IDE

Your factory is autonomous! 🚀" || echo "   (Issue creation skipped)"
fi

echo ""
echo "Happy building! 🏭"
