# Factory Remote Installation Guide

This guide explains how to use the `install_remote.py` script to transplant the Factory Template autonomous system into a remote repository.

## Overview

The `install_remote.py` script automates the process of:
1. Cloning the target repository
2. Injecting factory components (workflows, scripts, configs, constitution)
3. Committing and pushing the changes
4. Validating the installation

## Prerequisites

### 1. GitHub Personal Access Token (FACTORY_ADMIN_TOKEN)

You need a GitHub Personal Access Token with the following scopes:
- `repo` - Full control of private repositories
- `workflow` - Update GitHub Action workflows

**Create your token at:** https://github.com/settings/tokens

### 2. Environment Setup

Export the token as an environment variable:

```bash
export FACTORY_ADMIN_TOKEN="your_github_token_here"
```

## Usage

### Basic Command

```bash
python3 scripts/install_remote.py <target_repo_url>
```

### Example: Install to VoxGuard

```bash
export FACTORY_ADMIN_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"
python3 scripts/install_remote.py https://github.com/abiolaogu/VoxGuard
```

## What Gets Installed

The script installs the following factory components:

### 1. Workflows (`.github/workflows/`)
- `claude.yml` - Universal Factory Worker (Claude Code Action)
- `repository-assessment.yml` - Automatic repository assessment
- `self-healing.yml` - Self-healing automation
- `growth-engine.yml` - Autonomous growth system
- `frontend-lifecycle.yml` - Frontend development automation
- And more...

### 2. Scripts (`scripts/`)
- `agents/` - Autonomous agents (repo_assessor, repo_improver, etc.)
- `universal/` - Universal build/test/lint scripts
- `autonomous_growth.py` - Growth automation
- `self_heal.py` - Self-healing logic
- And more...

### 3. Configuration (`config/`)
- `factory_constitution.md` - Factory rules and guidelines
- `ideal-customer-profile.yaml` - ICP definitions
- `system_architect.txt` - Architecture guidelines
- `janitor_compliance.txt` - Code quality standards
- And more...

### 4. Constitution (`CLAUDE.md`)
- Factory setup requirements
- Universal rules and directives
- Tech stack detection
- Common tasks and workflows

### 5. Dependencies (`requirements.txt`)
- Python packages required by factory scripts

## Installation Process

The script performs these steps:

### Step 1: Clone Target Repository
```
➤ Cloning target repository...
  ✓ Repository cloned successfully
```

### Step 2: Inject Factory Components
```
➤ Injecting factory components...
  ✓ Installed .github/workflows/
  ✓ Installed scripts/
  ✓ Installed config/
  ✓ Installed CLAUDE.md
  ✓ Installed requirements.txt
```

### Step 3: Commit and Push
```
➤ Committing factory upgrade...
  ✓ Changes committed

➤ Pushing to remote repository...
  ✓ Successfully pushed to remote
```

### Step 4: Validate Installation
```
➤ Validating installation...
  ✓ All components validated
```

## Important Notes

### Preserving Existing Code
- The script **DOES NOT** overwrite existing source code
- Only factory components are added/updated
- The target's `.git` history is preserved
- Factory files take precedence (factory is source of truth)

### Branch Targeting
- By default, pushes to the `main` branch
- Falls back to `master` if `main` doesn't exist
- The script will fail if permissions are insufficient

### Handling Conflicts
- Factory components always override existing versions
- If a factory file exists in target, it will be replaced
- This ensures the target gets the latest factory version

## Post-Installation

After successful installation, the target repository needs:

### 1. Configure Required Secrets

Navigate to **Settings → Secrets and variables → Actions** and add:

#### Critical Secrets:
- **ANTHROPIC_API_KEY** - For Claude Code Action
  - Get at: https://console.anthropic.com/

- **FACTORY_ADMIN_TOKEN** - For repository management
  - Required scopes: `repo` and `workflow`
  - Create at: https://github.com/settings/tokens

#### Optional Secrets (for Frontend Factory):
- **HASURA_ENDPOINT** - Hasura GraphQL endpoint
- **HASURA_ADMIN_SECRET** - Hasura admin secret
- **WORKIK_API_KEY** - Workik API key

### 2. Automatic Assessment

Once configured, the factory will automatically:
1. Assess repository completion status (0-100%)
2. Determine if project goals are achieved
3. Take action: IMPROVE (fix gaps) or CONTINUE_DEVELOPMENT
4. Generate missing PRD and documentation
5. Create GitHub issues with improvement recommendations

## Troubleshooting

### Error: FACTORY_ADMIN_TOKEN not set

**Solution:** Export your GitHub token:
```bash
export FACTORY_ADMIN_TOKEN="your_token_here"
```

### Error: Permission denied (push)

**Causes:**
- Token doesn't have `repo` or `workflow` scopes
- You don't have write access to the target repository
- The repository is archived or locked

**Solution:**
1. Verify token permissions at https://github.com/settings/tokens
2. Ensure you're a collaborator on the target repo

### Error: Repository not found

**Causes:**
- Invalid repository URL
- Repository is private and token doesn't have access
- Repository doesn't exist

**Solution:**
1. Verify the URL format: `https://github.com/owner/repo`
2. Check repository access permissions

### Error: Command failed (git clone)

**Causes:**
- Network connectivity issues
- Invalid authentication
- Repository too large

**Solution:**
1. Test your network connection
2. Verify FACTORY_ADMIN_TOKEN is valid
3. Try cloning manually first to diagnose

## Using from CI/CD

To use this script in a GitHub Actions workflow:

```yaml
name: Install Factory to Repository

on:
  workflow_dispatch:
    inputs:
      target_repo:
        description: 'Target repository URL'
        required: true
        type: string

jobs:
  install:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout factory template
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Execute Factory Installation
        env:
          FACTORY_ADMIN_TOKEN: ${{ secrets.FACTORY_ADMIN_TOKEN }}
        run: |
          python3 scripts/install_remote.py ${{ inputs.target_repo }}
```

## Security Considerations

### Token Security
- **NEVER** commit your FACTORY_ADMIN_TOKEN to git
- **NEVER** print the token in logs (script prevents this)
- Store tokens in GitHub Secrets or environment variables only
- Rotate tokens regularly

### Repository Access
- Only install to repositories you own or have explicit permission to modify
- Review changes before pushing to production repositories
- Test on a fork or test repository first

### Review Changes
After installation, review:
1. All workflow files in `.github/workflows/`
2. Scripts in `scripts/` directory
3. Configuration in `config/` directory
4. The CLAUDE.md constitution

## Support

For issues or questions:
1. Check this README first
2. Review the main factory documentation
3. Open an issue in the factory-template repository
4. Contact the factory maintainers

## Version Information

- Script: `scripts/install_remote.py`
- Created: 2026-02-02
- Compatible with: Factory Template v1.0+

---

**Generated with [Claude Code](https://claude.ai/code)**
