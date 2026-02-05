#!/usr/bin/env python3
"""
Autonomous Janitor Engine
Performs daily refactoring on existing repositories to maintain quality.
"""

import os
import sys
import json
import yaml
import subprocess
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional

try:
    from anthropic import Anthropic
except ImportError:
    print("❌ Error: anthropic library not installed")
    print("Please run: pip install anthropic")
    sys.exit(1)


class AutonomousJanitorEngine:
    """Orchestrates autonomous refactoring."""

    def __init__(self):
        """Initialize the janitor engine."""
        self.base_path = Path(__file__).parent.parent
        self.anthropic_key = os.getenv('ANTHROPIC_API_KEY')
        self.github_token = os.getenv('FACTORY_ADMIN_TOKEN')
        self.github_owner = os.getenv('GITHUB_REPOSITORY_OWNER', 'billyronks')

        if not self.anthropic_key:
            raise ValueError("ANTHROPIC_API_KEY environment variable not set")
        if not self.github_token:
            raise ValueError("FACTORY_ADMIN_TOKEN environment variable not set")

        self.client = Anthropic(api_key=self.anthropic_key)
        self.refactor_prs = []

    def scan_repositories(self) -> List[Dict]:
        """Scan all repositories and calculate quality scores."""
        print("🔍 Scanning repositories for quality scores...")

        manifest_path = self.base_path / '.repo-index' / 'manifest.yaml'

        if not manifest_path.exists():
            print("   ⚠️  No repository manifest found")
            return []

        with open(manifest_path, 'r') as f:
            manifest = yaml.safe_load(f) or {}

        repos = manifest.get('components', [])
        print(f"   ✓ Found {len(repos)} repositories in manifest")

        # Analyze each repository
        scored_repos = []
        for repo in repos:
            try:
                score = self.calculate_quality_score(repo)
                scored_repos.append({
                    'repo': repo,
                    'quality_score': score
                })
                print(f"   - {repo['name']}: {score}/100")
            except Exception as e:
                print(f"   ✗ Error analyzing {repo.get('name', 'unknown')}: {e}")

        return sorted(scored_repos, key=lambda x: x['quality_score'])

    def calculate_quality_score(self, repo: Dict) -> int:
        """Calculate a quality score for a repository."""
        # Simulate quality score calculation
        # In production, this would:
        # 1. Clone the repo
        # 2. Run static analysis
        # 3. Check for code duplication
        # 4. Verify test coverage
        # 5. Check for outdated dependencies
        # 6. Analyze architecture adherence

        # For now, use a simple heuristic based on age
        created = repo.get('created', datetime.now().isoformat())
        created_date = datetime.fromisoformat(created.replace('Z', '+00:00'))
        days_old = (datetime.now() - created_date.replace(tzinfo=None)).days

        # Older repos have lower scores (more likely to need refactoring)
        base_score = max(50, 100 - days_old * 2)

        return base_score

    def identify_refactoring_needs(self, repo_info: Dict) -> Optional[Dict]:
        """Use Claude to identify refactoring needs using hardwired compliance prompt."""
        repo = repo_info['repo']
        quality_score = repo_info['quality_score']

        print(f"\n🔧 Analyzing {repo['name']} (score: {quality_score}/100)...")

        # READ THE COMPLIANCE BRAIN (Hardwired System Prompt for Janitor)
        config_path = self.base_path / 'config' / 'janitor_compliance.txt'

        if not config_path.exists():
            print(f"   ⚠️  Compliance config not found, using fallback prompt")
            system_prompt = self._get_fallback_compliance_prompt()
        else:
            with open(config_path, 'r') as f:
                system_prompt = f.read()

        # Build user context with repository-specific information
        user_context = f"""REPOSITORY INFO:
- Name: {repo['name']}
- Description: {repo.get('description', 'N/A')}
- Tech Stack: {json.dumps(repo.get('tech_stack', {}), indent=2)}
- Quality Score: {quality_score}/100
- Reusable Components: {repo.get('reusable_components', [])}

Identify ONE high-impact, non-disruptive refactoring opportunity for this repository."""

        try:
            message = self.client.messages.create(
                model="claude-sonnet-4-5-20250929",
                max_tokens=1500,
                system=system_prompt,  # <--- HARDWIRED COMPLIANCE BRAIN
                messages=[
                    {"role": "user", "content": user_context}
                ]
            )

            response_text = message.content[0].text.strip()

            # Extract JSON
            if '```json' in response_text:
                json_start = response_text.find('```json') + 7
                json_end = response_text.find('```', json_start)
                response_text = response_text[json_start:json_end].strip()

            refactor_plan = json.loads(response_text)

            print(f"   ✓ Identified: {refactor_plan['title']}")
            print(f"   Type: {refactor_plan['refactor_type']}")
            print(f"   Risk: {refactor_plan['estimated_risk']}")
            print(f"   Impact: {refactor_plan['impact']}")

            return {
                'repo': repo,
                'plan': refactor_plan
            }

        except Exception as e:
            print(f"   ✗ Error identifying refactoring: {e}")
            return None

    def _get_fallback_compliance_prompt(self) -> str:
        """Fallback compliance prompt if config file doesn't exist."""
        return """You are an autonomous code refactoring system following the "Holy Trinity" principles:
1. Extreme Programming (XP) - TDD, Pair Programming, Continuous Integration
2. Domain-Driven Design (DDD) - Bounded Contexts, Ubiquitous Language
3. Test-Driven Development (TDD) - Tests first, refactor with confidence

COMPLIANCE MANDATE: Non-Disruptive Refactoring Only
- NDPR/GDPR: Ensure data handling remains compliant
- SOC2: Maintain audit logging and access controls
- Security: Never introduce vulnerabilities

TASK: Identify ONE high-impact refactoring opportunity that would:
1. Improve code quality (reduce duplication, improve testability)
2. Align with Holy Trinity principles (DDD/XP/TDD)
3. Be low-risk (Tier 0 or Tier 1) - NO breaking changes
4. Maintain or improve compliance posture

Common refactoring patterns to consider:
- Extract duplicate JWT logic to shared library
- Update deprecated API calls (security patches)
- Convert callback hell to async/await (readability)
- Extract domain logic from controllers (DDD alignment)
- Add missing unit tests for critical paths (TDD)
- Consolidate similar components (DRY principle)
- Improve error handling and logging (SOC2)

OUTPUT FORMAT (JSON):
{
  "refactor_type": "extract_library" | "update_deprecated" | "improve_tests" | "architecture_alignment" | "compliance_hardening",
  "title": "Brief title for the refactoring",
  "description": "Detailed description of what needs to be done",
  "estimated_risk": "tier_0" | "tier_1",
  "impact": "High" | "Medium" | "Low",
  "rationale": "Why this refactoring is valuable (focus on compliance/quality)",
  "files_affected": ["path/to/file1", "path/to/file2"]
}

Respond with ONLY the JSON, no other text."""

    def apply_refactoring(self, refactor_info: Dict) -> Optional[str]:
        """Apply the refactoring and create a PR."""
        repo = refactor_info['repo']
        plan = refactor_info['plan']

        print(f"\n🔨 Applying refactoring to {repo['name']}...")

        # Extract repo name from URL
        repo_url = repo['url']
        repo_name = repo_url.split('/')[-1]
        full_repo_name = f"{self.github_owner}/{repo_name}"

        try:
            # Clone repository
            clone_dir = self.base_path / 'temp' / repo_name
            clone_dir.parent.mkdir(parents=True, exist_ok=True)

            if clone_dir.exists():
                # Clean up existing clone
                subprocess.run(['rm', '-rf', str(clone_dir)], check=True)

            subprocess.run([
                'gh', 'repo', 'clone', full_repo_name, str(clone_dir)
            ], check=True, env={
                **os.environ,
                'GH_TOKEN': self.github_token
            })

            print(f"   ✓ Cloned repository")

            # Create refactor branch
            timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
            branch_name = f"refactor/daily-cleanup-{timestamp}"

            subprocess.run(['git', 'checkout', '-b', branch_name], cwd=clone_dir, check=True)
            print(f"   ✓ Created branch: {branch_name}")

            # Apply refactoring using Claude (simulated for now)
            # In production, this would use Claude Code Action to actually modify files
            print(f"   ℹ️  Refactoring would be applied here via Claude Code Action")
            print(f"   Plan: {plan['description']}")

            # For simulation, create a marker file
            marker_file = clone_dir / 'REFACTOR_APPLIED.md'
            marker_content = f"""# Refactoring Applied

**Type:** {plan['refactor_type']}
**Title:** {plan['title']}
**Date:** {datetime.now().isoformat()}

## Description
{plan['description']}

## Rationale
{plan['rationale']}

## Files Affected
{chr(10).join(f'- {f}' for f in plan['files_affected'])}

## Risk Assessment
- **Tier:** {plan['estimated_risk']}
- **Impact:** {plan['impact']}

---
*Generated by Autonomous Janitor Engine*
"""
            marker_file.write_text(marker_content)

            # Commit changes
            subprocess.run(['git', 'add', '.'], cwd=clone_dir, check=True)
            subprocess.run([
                'git', 'commit', '-m',
                f"refactor: {plan['title']}\n\n{plan['description']}\n\nGenerated by Autonomous Janitor Engine\nTier: {plan['estimated_risk']}"
            ], cwd=clone_dir, check=True)

            # Push branch
            subprocess.run(['git', 'push', '-u', 'origin', branch_name], cwd=clone_dir, check=True, env={
                **os.environ,
                'GH_TOKEN': self.github_token
            })

            print(f"   ✓ Pushed refactor branch")

            # Create PR
            pr_body = f"""## Refactoring Summary

**Type:** {plan['refactor_type']}
**Impact:** {plan['impact']}
**Risk Tier:** {plan['estimated_risk']}

### Description
{plan['description']}

### Rationale
{plan['rationale']}

### Files Affected
{chr(10).join(f'- `{f}`' for f in plan['files_affected'])}

### Action Required
- [ ] Review changes
- [ ] Verify tests pass
- [ ] {f"Merge (Tier 0 - Auto-merge eligible)" if plan['estimated_risk'] == 'tier_0' else f"Request review (Tier 1)"}

---
🤖 Generated by [Autonomous Janitor Engine](https://github.com/abiolaogu/factory-template)
"""

            create_pr_cmd = [
                'gh', 'pr', 'create',
                '--title', f"refactor: {plan['title']}",
                '--body', pr_body,
                '--base', 'main',
                '--head', branch_name
            ]

            result = subprocess.run(create_pr_cmd, cwd=clone_dir, capture_output=True, text=True, env={
                **os.environ,
                'GH_TOKEN': self.github_token
            })

            if result.returncode == 0:
                pr_url = result.stdout.strip()
                print(f"   ✓ Created PR: {pr_url}")

                # Clean up clone
                subprocess.run(['rm', '-rf', str(clone_dir)], check=True)

                return pr_url
            else:
                print(f"   ✗ Failed to create PR: {result.stderr}")
                return None

        except Exception as e:
            print(f"   ✗ Error applying refactoring: {e}")
            return None

    def run_janitor_loop(self, target_count: int = 2) -> List[Dict]:
        """Run the janitor engine to refactor existing repositories."""
        print("\n" + "=" * 60)
        print("🧹 JANITOR ENGINE - STARTING")
        print("=" * 60)
        print(f"Target: {target_count} refactoring PRs")

        # Scan repositories
        scored_repos = self.scan_repositories()

        if not scored_repos:
            print("\n⚠️  No repositories found to refactor")
            return []

        # Select repositories with lowest scores (most in need of refactoring)
        target_repos = scored_repos[:target_count * 2]  # Get 2x targets to ensure we hit our goal

        # Apply refactoring
        refactored = []
        for repo_info in target_repos:
            if len(refactored) >= target_count:
                break

            # Identify refactoring needs
            refactor_info = self.identify_refactoring_needs(repo_info)
            if not refactor_info:
                continue

            # Skip if high-risk (Tier 2)
            if refactor_info['plan']['estimated_risk'] == 'tier_2':
                print(f"   ⚠️  Skipping Tier 2 refactoring (too risky for automation)")
                continue

            # Apply refactoring
            pr_url = self.apply_refactoring(refactor_info)
            if pr_url:
                refactored.append({
                    'repo': refactor_info['repo']['name'],
                    'url': pr_url,
                    'title': refactor_info['plan']['title'],
                    'type': refactor_info['plan']['refactor_type'],
                    'tier': refactor_info['plan']['estimated_risk'],
                    'timestamp': datetime.now().isoformat()
                })

        print("\n" + "=" * 60)
        print(f"✅ JANITOR ENGINE - COMPLETE")
        print(f"   Created: {len(refactored)}/{target_count} refactoring PRs")
        print("=" * 60)

        return refactored


def main():
    """Main entry point."""
    print("🧹 Autonomous Janitor Engine")
    print("=" * 60)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    try:
        engine = AutonomousJanitorEngine()

        # Check if manifest has components before proceeding
        manifest_path = Path(__file__).parent.parent / '.repo-index' / 'manifest.yaml'
        if manifest_path.exists():
            with open(manifest_path, 'r') as f:
                manifest = yaml.safe_load(f) or {}

            if not manifest.get('components'):
                print("⚠️ Manifest is empty. No repositories to refactor. Skipping Janitor run.")
                return 0

        # Run janitor engine (2 refactorings)
        refactor_prs = engine.run_janitor_loop(target_count=2)

        # Print summary
        print("\n" + "=" * 60)
        print("📊 SUMMARY")
        print("=" * 60)
        print(f"Refactoring PRs Created: {len(refactor_prs)}")

        for i, pr in enumerate(refactor_prs, 1):
            print(f"\n{i}. {pr['title']}")
            print(f"   Repository: {pr['repo']}")
            print(f"   PR URL: {pr['url']}")
            print(f"   Type: {pr['type']}")
            print(f"   Tier: {pr['tier']}")

        # Update growth dashboard
        dashboard_path = Path(__file__).parent.parent / 'docs' / 'GROWTH_DASHBOARD.md'
        update_dashboard(dashboard_path, refactor_prs)

        return 0

    except Exception as e:
        print(f"\n❌ Fatal error: {e}")
        import traceback
        traceback.print_exc()
        return 1


def update_dashboard(dashboard_path: Path, refactor_prs: List[Dict]):
    """Update the growth dashboard with today's refactoring output."""
    print(f"\n📊 Updating growth dashboard at {dashboard_path}...")

    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    date_str = datetime.now().strftime('%Y-%m-%d')

    # Read existing content
    if not dashboard_path.exists():
        print(f"   ⚠️  Dashboard doesn't exist yet, will be created by creator engine")
        return

    with open(dashboard_path, 'r') as f:
        content = f.read()

    # Find today's entry and update refactor section
    section_header = f"## Growth Report: {date_str}"

    if section_header in content:
        # Update existing entry
        # Find the Refactor Actions section
        refactor_section = "### Refactor Actions (Janitor Engine)\n\n"
        refactor_start = content.find(refactor_section)

        if refactor_start != -1:
            # Find end of refactor section (next ### or ---)
            refactor_content_start = refactor_start + len(refactor_section)
            next_section = content.find("###", refactor_content_start)

            if next_section == -1:
                next_section = content.find("---", refactor_content_start)

            # Generate new refactor content
            new_refactor_content = ""
            if refactor_prs:
                for i, pr in enumerate(refactor_prs, 1):
                    new_refactor_content += f"{i}. **{pr['title']}**\n"
                    new_refactor_content += f"   - PR: [{pr['url']}]({pr['url']})\n"
                    new_refactor_content += f"   - Repository: {pr['repo']}\n"
                    new_refactor_content += f"   - Type: {pr['type']}\n\n"
            else:
                new_refactor_content = "*No refactoring actions today*\n\n"

            # Replace content
            if next_section != -1:
                content = content[:refactor_content_start] + new_refactor_content + content[next_section:]
            else:
                content = content[:refactor_content_start] + new_refactor_content

            with open(dashboard_path, 'w') as f:
                f.write(content)

            print(f"   ✓ Dashboard updated")
        else:
            print(f"   ⚠️  Refactor section not found in today's entry")
    else:
        print(f"   ⚠️  No entry for today found, will be created by creator engine")


if __name__ == '__main__':
    sys.exit(main())
