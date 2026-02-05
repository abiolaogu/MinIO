#!/usr/bin/env python3
"""
Code Auditor Agent - Internal Reflection Bot
Walks the codebase, analyzes architecture for XP/DDD/TDD compliance,
and creates GitHub issues for critical gaps or code smells.
"""

import os
import json
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional
import requests
from anthropic import Anthropic

# GitHub Configuration
GITHUB_API_URL = "https://api.github.com"
GITHUB_REPO = os.environ.get("GITHUB_REPOSITORY", "")

# Files and directories to ignore
IGNORE_PATTERNS = {
    '.git', '.github', 'node_modules', '__pycache__', '.venv', 'venv',
    'dist', 'build', '.next', '.cache', 'coverage', '.pytest_cache',
    '*.pyc', '*.pyo', '*.log', '*.md', 'package-lock.json', 'yarn.lock'
}

# Key file patterns to focus on
KEY_PATTERNS = {
    'config': ['*.yml', '*.yaml', '*.json', '*.toml', '*.ini'],
    'python': ['*.py'],
    'javascript': ['*.js', '*.jsx', '*.ts', '*.tsx'],
    'tests': ['*test*.py', '*_test.py', 'test_*.py', '*.test.js', '*.spec.js'],
    'docs': ['README.md', 'CONTRIBUTING.md', 'ARCHITECTURE.md']
}


def should_ignore(path: Path) -> bool:
    """
    Check if a path should be ignored based on patterns.

    Args:
        path: Path to check

    Returns:
        True if should be ignored, False otherwise
    """
    path_str = str(path)

    for pattern in IGNORE_PATTERNS:
        if pattern.startswith('*'):
            if path_str.endswith(pattern[1:]):
                return True
        elif pattern in path_str:
            return True

    return False


def generate_repo_structure(base_path: Path, max_depth: int = 3) -> str:
    """
    Generate a tree-like structure of the repository.

    Args:
        base_path: Base path of the repository
        max_depth: Maximum depth to traverse

    Returns:
        String representation of the directory structure
    """
    print("📁 Generating repository structure...")

    structure_lines = [f"Repository Structure: {base_path.name}/\n"]

    def walk_directory(path: Path, prefix: str = "", depth: int = 0):
        if depth > max_depth or should_ignore(path):
            return

        try:
            items = sorted(path.iterdir(), key=lambda x: (not x.is_dir(), x.name))

            for i, item in enumerate(items):
                if should_ignore(item):
                    continue

                is_last = i == len(items) - 1
                current_prefix = "└── " if is_last else "├── "
                next_prefix = "    " if is_last else "│   "

                structure_lines.append(f"{prefix}{current_prefix}{item.name}")

                if item.is_dir():
                    walk_directory(item, prefix + next_prefix, depth + 1)

        except PermissionError:
            pass

    walk_directory(base_path)

    structure = "\n".join(structure_lines)
    print(f"   ✓ Generated structure ({len(structure_lines)} items)")
    return structure


def collect_key_files(base_path: Path) -> Dict[str, str]:
    """
    Collect contents of key files for analysis.

    Args:
        base_path: Base path of the repository

    Returns:
        Dictionary mapping file paths to their contents
    """
    print("📄 Collecting key file contents...")

    key_files = {}
    file_count = 0
    max_files = 20  # Limit to prevent overwhelming Claude
    max_file_size = 5000  # Max chars per file

    # Priority order for file collection
    priority_files = [
        'README.md',
        'CLAUDE.md',
        'requirements.txt',
        'package.json',
        'pyproject.toml',
        'setup.py',
        'Dockerfile',
        '.github/workflows/*.yml'
    ]

    # Collect priority files first
    for pattern in priority_files:
        if file_count >= max_files:
            break

        if '*' in pattern:
            # Handle glob patterns
            parts = pattern.split('/')
            if len(parts) > 1:
                search_dir = base_path / '/'.join(parts[:-1])
                if search_dir.exists():
                    for file_path in search_dir.glob(parts[-1]):
                        if file_count >= max_files or should_ignore(file_path):
                            continue

                        try:
                            content = file_path.read_text(encoding='utf-8')
                            if len(content) > max_file_size:
                                content = content[:max_file_size] + "\n... (truncated)"

                            key_files[str(file_path.relative_to(base_path))] = content
                            file_count += 1
                        except Exception:
                            pass
        else:
            file_path = base_path / pattern
            if file_path.exists():
                try:
                    content = file_path.read_text(encoding='utf-8')
                    if len(content) > max_file_size:
                        content = content[:max_file_size] + "\n... (truncated)"

                    key_files[pattern] = content
                    file_count += 1
                except Exception:
                    pass

    # Collect sample Python files from scripts/
    scripts_dir = base_path / 'scripts'
    if scripts_dir.exists() and file_count < max_files:
        for py_file in scripts_dir.glob('*.py'):
            if file_count >= max_files or should_ignore(py_file):
                continue

            try:
                content = py_file.read_text(encoding='utf-8')
                if len(content) > max_file_size:
                    content = content[:max_file_size] + "\n... (truncated)"

                key_files[str(py_file.relative_to(base_path))] = content
                file_count += 1
            except Exception:
                pass

    print(f"   ✓ Collected {len(key_files)} key files")
    return key_files


def analyze_architecture_with_claude(structure: str, key_files: Dict[str, str]) -> Optional[Dict]:
    """
    Send repository summary to Claude for architecture analysis.

    Args:
        structure: Repository structure tree
        key_files: Dictionary of key file contents

    Returns:
        Dictionary with issue details, or None if no critical gaps found
    """
    print("\n🤖 Analyzing architecture with Claude...")

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("   ✗ Error: ANTHROPIC_API_KEY not found in environment")
        return None

    try:
        client = Anthropic(api_key=api_key)

        # Format key files for Claude
        files_text = "\n\n".join([
            f"### File: {path}\n```\n{content}\n```"
            for path, content in list(key_files.items())[:15]  # Limit to prevent token overflow
        ])

        prompt = f"""You are the Lead Architect for an autonomous software factory. Analyze this codebase for compliance with the "Holy Trinity" principles:

**XP (Extreme Programming):**
- Simple design
- Continuous integration
- Collective code ownership
- Sustainable pace

**DDD (Domain-Driven Design):**
- Clear domain boundaries
- Ubiquitous language
- Domain models separate from infrastructure
- Aggregates and entities properly defined

**TDD (Test-Driven Development):**
- Tests written before code
- High test coverage
- Tests as documentation
- Fast feedback loops

## Repository Structure
```
{structure}
```

## Key Files
{files_text}

Your task: Find ONE critical architectural gap or code smell. Focus on:
- Missing or inadequate tests
- Business logic mixed with infrastructure (controllers, views)
- Hardcoded secrets or configuration
- Lack of domain modeling
- Tight coupling between components
- Missing CI/CD checks
- No documentation for key workflows

If you find a critical issue, respond with a JSON object in this format:
{{
    "found": true,
    "issue_name": "Brief name of the issue (max 50 chars)",
    "category": "XP" | "DDD" | "TDD",
    "severity": "critical" | "high" | "medium",
    "description": "Clear description of the architectural gap (2-3 sentences)",
    "location": "Specific file paths or areas affected",
    "proposed_fix": "Brief strategy to fix this issue (2-3 bullet points)"
}}

If no critical issues are found, respond with:
{{
    "found": false,
    "summary": "Brief summary of the codebase quality"
}}

Respond ONLY with the JSON object, no other text."""

        response = client.messages.create(
            model="claude-sonnet-4-5-20250929",
            max_tokens=1500,
            messages=[{
                "role": "user",
                "content": prompt
            }]
        )

        # Parse Claude's response
        response_text = response.content[0].text.strip()

        # Extract JSON from response (in case Claude adds explanation)
        if "```json" in response_text:
            response_text = response_text.split("```json")[1].split("```")[0].strip()
        elif "```" in response_text:
            response_text = response_text.split("```")[1].split("```")[0].strip()

        result = json.loads(response_text)

        if result.get("found"):
            print(f"   ✓ Found issue: {result['issue_name']} ({result['category']})")
            return result
        else:
            print(f"   ℹ️  No critical issues found: {result.get('summary', 'Codebase looks healthy')}")
            return None

    except Exception as e:
        print(f"   ✗ Error analyzing with Claude: {e}")
        import traceback
        traceback.print_exc()
        return None


def create_github_issue(issue: Dict) -> bool:
    """
    Create a GitHub issue for the identified architectural gap.

    Args:
        issue: Dictionary with issue details

    Returns:
        True if issue was created successfully, False otherwise
    """
    print(f"\n📝 Creating GitHub issue for: {issue['issue_name']}")

    github_token = os.environ.get("GITHUB_TOKEN")
    if not github_token:
        print("   ✗ Error: GITHUB_TOKEN not found in environment")
        return False

    if not GITHUB_REPO:
        print("   ✗ Error: GITHUB_REPOSITORY not found in environment")
        return False

    try:
        # Prepare issue body
        fix_strategy = issue['proposed_fix']
        if isinstance(fix_strategy, list):
            fix_strategy = "\n".join([f"- {item}" for item in fix_strategy])

        severity_emoji = {
            'critical': '🚨',
            'high': '⚠️',
            'medium': '📋'
        }

        body = f"""{severity_emoji.get(issue['severity'], '📋')} **Severity:** {issue['severity'].title()}

## Description
{issue['description']}

## Location
{issue['location']}

## Proposed Fix Strategy
{fix_strategy}

## Related Principle
**{issue['category']}** - {_get_principle_description(issue['category'])}

---
*Generated by Code Auditor Agent on {datetime.now().strftime('%Y-%m-%d at %H:%M UTC')}*"""

        # Create issue via GitHub API
        url = f"{GITHUB_API_URL}/repos/{GITHUB_REPO}/issues"
        headers = {
            "Authorization": f"token {github_token}",
            "Accept": "application/vnd.github.v3+json"
        }
        payload = {
            "title": f"🔧 Architecture Gap: {issue['issue_name']}",
            "body": body,
            "labels": ["code-auditor", "architecture", issue['category'].lower(), issue['severity']]
        }

        response = requests.post(url, headers=headers, json=payload, timeout=10)
        response.raise_for_status()

        issue_data = response.json()
        issue_url = issue_data.get('html_url', '')

        print(f"   ✓ Issue created: {issue_url}")
        return True

    except Exception as e:
        print(f"   ✗ Error creating GitHub issue: {e}")
        import traceback
        traceback.print_exc()
        return False


def _get_principle_description(category: str) -> str:
    """Get brief description of the principle category."""
    descriptions = {
        'XP': 'Extreme Programming - Simple design, continuous integration',
        'DDD': 'Domain-Driven Design - Clear boundaries, domain models',
        'TDD': 'Test-Driven Development - Tests first, high coverage'
    }
    return descriptions.get(category, 'Software engineering best practice')


def main():
    """Main execution function."""
    print("🔍 Code Auditor Agent - Starting Internal Reflection")
    print("=" * 70)

    try:
        # Get repository path
        repo_path = Path(__file__).parent.parent.parent

        # Generate repository structure
        structure = generate_repo_structure(repo_path)

        # Collect key files
        key_files = collect_key_files(repo_path)

        if not key_files:
            print("\n⚠️  No key files found. Exiting.")
            return 1

        # Analyze architecture with Claude
        issue = analyze_architecture_with_claude(structure, key_files)

        if issue and issue.get('found'):
            # Create GitHub issue
            success = create_github_issue(issue)

            if success:
                print("\n✅ Code Auditor completed successfully!")
                return 0
            else:
                print("\n⚠️  Failed to create GitHub issue")
                return 1
        else:
            print("\n✅ Code Auditor completed - No critical issues found")
            return 0

    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    try:
        exit(main())
    except KeyboardInterrupt:
        print("\n\n⚠️  Code Auditor interrupted by user")
        exit(130)
