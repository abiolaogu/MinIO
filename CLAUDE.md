# Autonomous Factory Constitution

## ⚠️ Setup Requirements

**CRITICAL:** Before using this Factory Template, you MUST configure the following secrets in your repository:

1. **ANTHROPIC_API_KEY**: Your Anthropic API key for Claude Code Action
   - Get your key at: https://console.anthropic.com/
   - Required for AI-powered product derivation

2. **FACTORY_ADMIN_TOKEN**: GitHub Personal Access Token (PAT)
   - Required scopes: `repo` and `workflow`
   - Used for creating repositories and managing workflows
   - Create at: https://github.com/settings/tokens

### Optional Secrets (for specific features)

The following secrets are **optional** and only required if you want to use the **Frontend Factory** feature:

3. **HASURA_ENDPOINT**: Your Hasura GraphQL endpoint URL
   - Required for: Frontend Factory workflow
   - Used to: Generate frontend code based on backend schema

4. **HASURA_ADMIN_SECRET**: Your Hasura admin secret key
   - Required for: Frontend Factory workflow
   - Used to: Access Hasura metadata for code generation

5. **WORKIK_API_KEY**: API key for Workik code generation service
   - Required for: Frontend Factory workflow
   - Used to: Generate scaffolded frontend code

**To add secrets:** Navigate to **Settings → Secrets and variables → Actions** in your repository.

### Lovable Integration Setup

**Connect Lovable:** The factory uses Lovable's GitHub App integration for design system synchronization. To set this up:
1. Go to [Lovable.dev](https://lovable.dev) → Settings → Integrations → GitHub
2. Install the Lovable App for this repository
3. When the factory pushes code to GitHub, Lovable automatically syncs the changes via the App integration

---

## Universal Rules

1. **The Prime Directive:** Speed is life. "Vibe coding" applies.

2. **Security:** NEVER print passwords or keys in logs.

3. **Identity:** You are an autonomous builder for BillyRonks Global.



## The Assembly Line

- **Tier 0:** Documentation, Tests, Text? -> **Auto-Merge**.

- **Tier 1:** Features, Logic? -> **Request Review**.

- **Tier 2:** Auth, Payments, Infra? -> **REQUIRE ADMIN APPROVAL**.



## Tech Stack Detection

- If you see `pubspec.yaml` -> Use **Flutter**.

- If you see `requirements.txt` -> Use **Python**.

- If you see `package.json` -> Use **Node/React**.



## Common Tasks

- **Repository Assessment:** When this template is forked/copied, it automatically assesses the repository and takes improvement actions. See `scripts/agents/repo_assessor.py` and `scripts/agents/repo_improver.py`.

- **Universal Transformation Kit:** Use `./scripts/install_transformation_kit.sh [TARGET_REPO]` to install the universal CI/CD system into any repository. See `docs/universal-transformation-kit.md` for full documentation.

- **System Audit:** For a comprehensive analysis of the factory's autonomy and compliance status, refer to `docs/AUTONOMY_COMPLIANCE_AUDIT.md`.

## Factory Purpose

This factory is an **Autonomous Repository Improvement System**. When forked or copied to a new repository:
1. It assesses repository completion status (0-100%)
2. Determines if project goals are achieved
3. Takes action: IMPROVE (fix gaps) or CONTINUE_DEVELOPMENT (build features)
4. Generates missing PRD and documentation
5. Creates GitHub issues with improvement recommendations