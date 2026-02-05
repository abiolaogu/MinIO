#!/usr/bin/env python3
"""
Self-Healing Script for Autonomous Factory
Analyzes CI/CD failures and attempts safe, automated fixes for Tier 0/1 issues.
"""

import os
import sys
import json
from pathlib import Path

def classify_failure_tier(workflow_name: str, failed_jobs: list) -> int:
    """
    Classify the failure tier based on workflow name and job content.

    Tier 0: Documentation, Tests, Research (Safe to auto-fix)
    Tier 1: Features, Frontend, Marketing (Consider auto-fix)
    Tier 2: Auth, Payments, Infrastructure (Escalate to humans)

    Returns: 0, 1, or 2
    """
    workflow_lower = workflow_name.lower()

    # Tier 2: High-risk infrastructure (NEVER auto-fix)
    tier2_keywords = [
        'deploy', 'production', 'infrastructure',
        'auth', 'payment', 'security', 'migration',
        'terraform', 'helm', 'k8s'
    ]
    if any(keyword in workflow_lower for keyword in tier2_keywords):
        return 2

    # Tier 0: Low-risk documentation/testing (Safe to auto-fix)
    tier0_keywords = [
        'test', 'lint', 'doc', 'research', 'alignment',
        'audit', 'scan', 'analysis'
    ]
    if any(keyword in workflow_lower for keyword in tier0_keywords):
        return 0

    # Tier 1: Feature development (Consider auto-fix)
    return 1


def analyze_common_failures() -> dict:
    """
    Analyze common failure patterns and return suggested fixes.

    Returns dict with:
    - 'fixable': bool
    - 'fix_type': str
    - 'description': str
    """
    # Check for common patterns in git status
    git_status = os.popen('git status --porcelain').read()

    # Pattern 1: Formatting/linting issues
    if any(file.endswith(('.py', '.js', '.ts', '.md')) for file in git_status.split('\n')):
        return {
            'fixable': True,
            'fix_type': 'formatting',
            'description': 'Potential formatting or linting issues detected'
        }

    # Pattern 2: Missing dependencies
    if Path('package.json').exists() or Path('requirements.txt').exists():
        return {
            'fixable': False,
            'fix_type': 'dependencies',
            'description': 'Dependency issues require manual investigation'
        }

    # Pattern 3: Type errors (require manual fix)
    return {
        'fixable': False,
        'fix_type': 'unknown',
        'description': 'Failure type requires manual investigation'
    }


def attempt_safe_fix() -> bool:
    """
    Attempt safe automated fixes for common issues.

    Returns: True if fix was applied, False otherwise
    """
    analysis = analyze_common_failures()

    if not analysis['fixable']:
        print(f"❌ Cannot auto-fix: {analysis['description']}")
        return False

    if analysis['fix_type'] == 'formatting':
        print("🔧 Attempting formatting fix...")

        # Try Python formatting with black
        if Path('requirements.txt').exists():
            os.system('pip install black 2>/dev/null')
            result = os.system('black . --quiet 2>/dev/null')
            if result == 0:
                print("✅ Applied Python formatting with black")
                return True

        # Try JavaScript/TypeScript formatting with prettier
        if Path('package.json').exists():
            result = os.system('npx prettier --write . 2>/dev/null')
            if result == 0:
                print("✅ Applied JS/TS formatting with prettier")
                return True

    return False


def main():
    """Main self-healing logic."""

    # Get workflow context from environment
    workflow_name = os.getenv('GITHUB_WORKFLOW', 'Unknown')
    failed_jobs_json = os.getenv('FAILED_JOBS', '[]')

    try:
        failed_jobs = json.loads(failed_jobs_json)
    except json.JSONDecodeError:
        failed_jobs = []

    print(f"🔍 Analyzing failure in workflow: {workflow_name}")
    print(f"📋 Failed jobs: {', '.join(failed_jobs) if failed_jobs else 'Unknown'}")

    # Classify the failure tier
    tier = classify_failure_tier(workflow_name, failed_jobs)
    print(f"🏷️  Classified as Tier {tier}")

    # Tier 2: Never auto-fix, escalate to humans
    if tier == 2:
        print("⛔ Tier 2 failure detected - escalation required")
        print("🚨 High-risk system involved (auth/payments/infra)")
        sys.exit(1)

    # Tier 0/1: Attempt auto-fix
    print(f"🤖 Tier {tier} failure - attempting auto-heal...")

    fix_applied = attempt_safe_fix()

    if fix_applied:
        print("✅ Fix applied successfully")
        sys.exit(0)
    else:
        print("⚠️  No safe fix found - manual intervention recommended")
        sys.exit(1)


if __name__ == '__main__':
    main()
