#!/usr/bin/env python3
"""
Repository Assessor Agent
Analyzes a repository to determine:
1. If project goals have been achieved
2. If PRD exists (generates one if missing)
3. What important documentation is missing
4. Overall completion status
5. Uses PRD as source of truth for assessment
"""

import os
import json
import anthropic
import datetime
import time
from pathlib import Path


class RepoAssessor:
    def __init__(self, github_token, anthropic_api_key):
        self.github_token = github_token
        self.anthropic_api_key = anthropic_api_key
        self.client = anthropic.Anthropic(api_key=anthropic_api_key)
        self.prd_path = Path("docs/PRD.md")
        self.readme_path = Path("README.md")
        self.changelog_path = Path("docs/AI_CHANGELOG.md")

    def scan_repo_structure(self):
        """Generate a tree structure of the repository."""
        repo_root = Path.cwd()

        # Ignore common directories
        ignore_dirs = {'.git', 'node_modules', '__pycache__', '.venv', 'venv',
                      'dist', 'build', '.pytest_cache', 'coverage'}

        structure = []

        def walk_dir(path, prefix="", max_depth=4, current_depth=0):
            if current_depth > max_depth:
                return

            try:
                items = sorted(path.iterdir(), key=lambda x: (not x.is_dir(), x.name))
                for item in items:
                    if item.name in ignore_dirs or item.name.startswith('.'):
                        continue

                    rel_path = item.relative_to(repo_root)
                    if item.is_dir():
                        structure.append(f"{prefix}📁 {item.name}/")
                        walk_dir(item, prefix + "  ", max_depth, current_depth + 1)
                    else:
                        structure.append(f"{prefix}📄 {item.name}")
            except PermissionError:
                pass

        walk_dir(repo_root)
        return "\n".join(structure)

    def log_ai_action(self, agent_name: str, target: str, action: str, details: str):
        """Log AI agent action to AI_CHANGELOG.md"""
        timestamp = datetime.datetime.utcnow()
        date_str = timestamp.strftime("%Y-%m-%d")
        time_str = timestamp.strftime("%H:%M:%S")

        log_entry = f"| {date_str} | {time_str} | {agent_name} | {target} | {action} | {details} |"

        try:
            if not self.changelog_path.exists():
                print(f"⚠️ AI_CHANGELOG.md not found at {self.changelog_path}")
                return

            content = self.changelog_path.read_text(encoding='utf-8')
            lines = content.split('\n')

            # Find the last line of the operation log table (before the "---" separator)
            insert_index = len(lines)
            for i, line in enumerate(lines):
                if line.strip() == "---" and i > 0 and "Operation Log" in '\n'.join(lines[:i]):
                    insert_index = i
                    break

            lines.insert(insert_index, log_entry)

            self.changelog_path.write_text('\n'.join(lines), encoding='utf-8')
            print(f"✅ Logged action to AI_CHANGELOG.md: {action} on {target}")
        except Exception as e:
            print(f"⚠️ Failed to log to AI_CHANGELOG.md: {e}")

    def check_and_generate_prd(self):
        """
        Check if PRD exists. If not, generate one from README.
        Returns: (prd_exists: bool, prd_content: str)
        """
        # Check if PRD exists
        if self.prd_path.exists():
            print(f"✅ PRD found at {self.prd_path}")
            try:
                prd_content = self.prd_path.read_text(encoding='utf-8')
                return True, prd_content
            except Exception as e:
                print(f"⚠️ Error reading PRD: {e}")
                return True, ""

        # PRD is missing - generate it
        print(f"⚠️ PRD not found. Generating from README...")

        # Read README
        readme_content = ""
        if self.readme_path.exists():
            try:
                readme_content = self.readme_path.read_text(encoding='utf-8')
            except Exception as e:
                print(f"⚠️ Error reading README: {e}")
                readme_content = "No README.md found"

        # Scan file tree for context
        structure = self.scan_repo_structure()

        # Generate PRD using Claude
        prd_generation_prompt = f"""You are a senior product manager. Generate a comprehensive Product Requirements Document (PRD) based on the following repository information.

**README Content:**
```
{readme_content}
```

**Repository Structure:**
```
{structure}
```

**Instructions:**
1. Analyze the README and codebase structure
2. Infer the project's goals, target users, and core features
3. Create a professional PRD with the following sections:
   - Executive Summary
   - Product Vision
   - Core Features (with implementation status)
   - User Stories
   - Technical Requirements
   - Success Metrics

**Format:** Use markdown with clear headers and bullet points.
**Length:** Be comprehensive but concise (aim for 500-1000 lines).
"""

        try:
            response = self.client.messages.create(
                model="claude-3-5-sonnet-20241022",
                max_tokens=4000,
                messages=[{
                    "role": "user",
                    "content": prd_generation_prompt
                }]
            )

            prd_content = response.content[0].text

            # Save PRD
            self.prd_path.parent.mkdir(parents=True, exist_ok=True)
            self.prd_path.write_text(prd_content, encoding='utf-8')

            print(f"✅ Generated PRD at {self.prd_path}")

            # Log the action
            self.log_ai_action(
                agent_name="Repository Assessor",
                target="docs/PRD.md",
                action="GENERATE",
                details="Missing PRD detected. Auto-generated docs/PRD.md based on README."
            )

            return False, prd_content

        except Exception as e:
            print(f"❌ Error generating PRD: {e}")
            return False, ""

    def collect_key_files(self):
        """Collect contents of key documentation and configuration files."""
        key_files = [
            "README.md",
            "CLAUDE.md",
            "PRD.md",
            "docs/PRD.md",
            "PRODUCT_REQUIREMENTS.md",
            "package.json",
            "requirements.txt",
            "pubspec.yaml",
            "Cargo.toml",
            "go.mod",
            "pom.xml",
            "build.gradle",
            ".github/workflows/*.yml"
        ]

        collected = {}
        repo_root = Path.cwd()

        for pattern in key_files:
            if "*" in pattern:
                # Handle glob patterns
                from glob import glob
                matches = glob(pattern, recursive=True)
                for match in matches[:5]:  # Limit to first 5 workflow files
                    path = Path(match)
                    if path.exists() and path.is_file():
                        try:
                            content = path.read_text(encoding='utf-8')
                            collected[str(path)] = content[:2000]  # First 2000 chars
                        except Exception:
                            pass
            else:
                path = repo_root / pattern
                if path.exists() and path.is_file():
                    try:
                        content = path.read_text(encoding='utf-8')
                        collected[pattern] = content[:3000]  # First 3000 chars
                    except Exception:
                        pass

        return collected

    def assess_completion_status(self):
        """Use Claude to assess repository completion status using PRD as source of truth."""
        # Step 1: Check and generate PRD if needed
        prd_exists, prd_content = self.check_and_generate_prd()

        # Step 2: Collect repository information
        structure = self.scan_repo_structure()
        key_files = self.collect_key_files()

        # Build current state context
        current_state = f"""# Repository Structure
{structure}

# Key Files Content
"""
        for filename, content in key_files.items():
            current_state += f"\n## {filename}\n```\n{content}\n```\n"

        # Prompt Claude for PRD-based assessment
        prompt = """You are the Product Owner reviewing repository completion.

**YOUR ROLE:** Compare the Product Requirements Document (PRD) against the current repository state to identify gaps.

**Source of Truth (PRD):**
```
{PRD_CONTENT}
```

**Current Repository State:**
```
{CURRENT_STATE}
```

**Task:**
1. Compare the PRD requirements against the current codebase
2. Find implemented features that are broken or incomplete
3. Identify required features that are missing entirely
4. For each gap, provide a technical strategy for implementation

**Output Format:** Respond ONLY with this JSON:
{
  "goals_achieved": "YES|NO|PARTIAL",
  "prd_exists": true|false,
  "missing_docs": ["doc1", "doc2", ...],
  "completion_percentage": 0-100,
  "next_steps": "IMPROVE|CONTINUE_DEVELOPMENT",
  "reasoning": "Brief explanation comparing PRD vs actual implementation",
  "technical_strategy": "Step-by-step approach for fixing gaps",
  "scope_gaps": [
    {
      "feature_name": "Name of missing/broken feature from PRD",
      "issue_type": "MISSING|BROKEN|INCOMPLETE",
      "prd_requirement": "What the PRD specifies",
      "current_status": "What exists in the codebase",
      "fix_strategy": "What needs to be done",
      "technical_strategy": "How to implement it step-by-step"
    }
  ]
}
"""

        prompt = prompt.replace("{PRD_CONTENT}", prd_content[:5000])  # Limit PRD to 5000 chars
        prompt = prompt.replace("{CURRENT_STATE}", current_state)

        try:
            response = self.client.messages.create(
                model="claude-3-5-sonnet-20241022",
                max_tokens=2000,
                messages=[{
                    "role": "user",
                    "content": prompt
                }]
            )

            response_text = response.content[0].text

            # Extract JSON from response
            import re
            json_match = re.search(r'\{[^}]+\}', response_text, re.DOTALL)
            if json_match:
                assessment = json.loads(json_match.group(0))
                return assessment
            else:
                # Fallback
                return {
                    "goals_achieved": "PARTIAL",
                    "prd_exists": False,
                    "missing_docs": ["PRD.md", "API_DOCS.md", "DEPLOYMENT.md"],
                    "completion_percentage": 50,
                    "next_steps": "CONTINUE_DEVELOPMENT",
                    "reasoning": "Unable to parse repository properly"
                }
        except Exception as e:
            print(f"Error during assessment: {e}")
            return {
                "goals_achieved": "PARTIAL",
                "prd_exists": False,
                "missing_docs": ["PRD.md"],
                "completion_percentage": 50,
                "next_steps": "CONTINUE_DEVELOPMENT",
                "reasoning": f"Error: {str(e)}"
            }

    def create_scope_gap_issue(self, gap):
        """Create a GitHub issue for a scope gap detected by comparing PRD vs code.
        Uses 'double-tap' strategy: creates issue then posts comment to trigger workflow."""
        import requests

        if not self.github_token:
            print(f"⚠️ Cannot create issue (no GitHub token): {gap['feature_name']}")
            return None

        github_repo = os.getenv("GITHUB_REPOSITORY")
        if not github_repo:
            print(f"⚠️ Cannot create issue (no GITHUB_REPOSITORY env var)")
            return None

        url = f"https://api.github.com/repos/{github_repo}/issues"
        headers = {
            "Authorization": f"token {self.github_token}",
            "Accept": "application/vnd.github.v3+json"
        }

        # Build issue body (without @claude to avoid false triggers)
        issue_body = f"""**Automated PRD-Based Analysis:**

## Issue Type
{gap['issue_type']}

## PRD Requirement
{gap['prd_requirement']}

## Current Status
{gap['current_status']}

## Fix Strategy
{gap['fix_strategy']}

## Technical Strategy
{gap['technical_strategy']}

---

**Automated Request:**
@claude please analyze this issue and implement the solution."""

        issue_title = f"⚠️ Scope Gap: {gap['feature_name']}"

        # Determine label based on issue type
        issue_type_label = "bug" if gap['issue_type'] == "BROKEN" else "enhancement"

        data = {
            "title": issue_title,
            "body": issue_body,
            "labels": ["claude", issue_type_label, "scope-gap", "prd-compliance", "auto-fix"]
        }

        try:
            # Step 1: Create the issue
            response = requests.post(url, headers=headers, json=data)
            if response.status_code == 201:
                issue_data = response.json()
                issue_number = issue_data['number']
                issue_url = issue_data['html_url']
                print(f"✅ Created scope gap issue #{issue_number}: {issue_url}")

                # Log to AI_CHANGELOG
                self.log_ai_action(
                    agent_name="Repository Assessor",
                    target=github_repo,
                    action="ISSUE",
                    details=f"Created issue #{issue_number}: {issue_title}"
                )

                # Step 2: Wait 5 seconds (as requested)
                print(f"⏳ Waiting 5 seconds before posting trigger comment...")
                time.sleep(5)

                # Step 3: Post a comment to trigger the workflow (double-tap strategy)
                comment_url = f"https://api.github.com/repos/{github_repo}/issues/{issue_number}/comments"
                comment_data = {
                    "body": "@claude start"
                }

                comment_response = requests.post(comment_url, headers=headers, json=comment_data)
                if comment_response.status_code == 201:
                    print(f"✅ Posted trigger comment on issue #{issue_number}")
                else:
                    print(f"⚠️ Failed to post trigger comment: {comment_response.status_code}")
                    print(f"   Response: {comment_response.text}")

                return issue_number
            else:
                print(f"⚠️ Failed to create issue: {response.status_code}")
                print(f"   Response: {response.text}")
                return None
        except Exception as e:
            print(f"❌ Error creating issue: {e}")
            return None

    def run(self):
        """Run the assessment and return results."""
        print("🔍 Starting repository assessment...")

        assessment = self.assess_completion_status()

        print("\n📊 Assessment Results:")
        print(f"  Goals Achieved: {assessment['goals_achieved']}")
        print(f"  PRD Exists: {assessment['prd_exists']}")
        print(f"  Completion: {assessment['completion_percentage']}%")
        print(f"  Next Steps: {assessment['next_steps']}")
        print(f"  Reasoning: {assessment['reasoning']}")

        # Create scope gap issues if any detected
        if 'scope_gaps' in assessment and assessment['scope_gaps']:
            print(f"\n🔍 Found {len(assessment['scope_gaps'])} scope gaps. Creating issues...")
            for gap in assessment['scope_gaps']:
                self.create_scope_gap_issue(gap)

        # Save to file for next agent
        output_path = Path(".factory-assessment.json")
        output_path.write_text(json.dumps(assessment, indent=2))

        print(f"\n✅ Assessment saved to {output_path}")

        return assessment


if __name__ == "__main__":
    github_token = os.getenv("GITHUB_TOKEN")
    anthropic_api_key = os.getenv("ANTHROPIC_API_KEY")

    if not anthropic_api_key:
        print("❌ Error: ANTHROPIC_API_KEY environment variable not set")
        exit(1)

    assessor = RepoAssessor(github_token, anthropic_api_key)
    result = assessor.run()

    # Exit with status code based on next steps
    if result['next_steps'] == 'IMPROVE':
        exit(0)  # Ready for improvement
    else:
        exit(10)  # Needs continued development
