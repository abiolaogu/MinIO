#!/usr/bin/env python3
"""
Factory Setup Verification Script

Verifies that the factory template is properly configured with required secrets
and dependencies. Can be run locally or in CI/CD.
"""

import os
import sys
from pathlib import Path


def check_secret(name, env_var):
    """
    Check if a secret/environment variable is configured.

    Args:
        name: Human-readable name of the secret
        env_var: Environment variable name

    Returns:
        Tuple of (is_configured: bool, message: str)
    """
    value = os.getenv(env_var)

    if not value:
        return False, f"❌ {name} ({env_var}) is NOT configured"

    # Basic validation (don't print actual value for security)
    if len(value) < 10:
        return False, f"⚠️  {name} ({env_var}) looks invalid (too short)"

    return True, f"✅ {name} ({env_var}) is configured"


def check_file(path, description):
    """
    Check if a required file exists.

    Args:
        path: Path to file
        description: Human-readable description

    Returns:
        Tuple of (exists: bool, message: str)
    """
    if Path(path).exists():
        return True, f"✅ {description} exists at {path}"
    else:
        return False, f"❌ {description} missing at {path}"


def check_python_package(package_name):
    """
    Check if a Python package is installed.

    Args:
        package_name: Name of the package to check

    Returns:
        Tuple of (installed: bool, message: str)
    """
    try:
        __import__(package_name)
        return True, f"✅ Python package '{package_name}' is installed"
    except ImportError:
        return False, f"❌ Python package '{package_name}' is NOT installed"


def main():
    """Main verification function."""
    print("🏭 Factory Setup Verification")
    print("=" * 60)

    all_checks_passed = True
    warnings = []

    # ========================================
    # 1. Check Required Secrets
    # ========================================
    print("\n📋 Checking Required Secrets...")

    checks = [
        check_secret("Anthropic API Key", "ANTHROPIC_API_KEY"),
        check_secret("Factory Admin Token", "FACTORY_ADMIN_TOKEN"),
        check_secret("GitHub Token", "GITHUB_TOKEN"),
    ]

    for passed, message in checks:
        print(f"   {message}")
        if not passed:
            all_checks_passed = False

    # ========================================
    # 2. Check Required Files
    # ========================================
    print("\n📁 Checking Required Files...")

    file_checks = [
        check_file("CLAUDE.md", "Factory Constitution"),
        check_file(".github/workflows/hunter-loop.yml", "Trend Hunter Workflow"),
        check_file(".github/workflows/growth-engine.yml", "Growth Engine Workflow"),
        check_file(".github/workflows/claude.yml", "Claude Code Action Workflow"),
        check_file("scripts/agents/trend_hunter.py", "Trend Hunter Script"),
        check_file("scripts/agents/autonomous_growth.py", "Autonomous Growth Script"),
        check_file("docs/USER_MANUAL.md", "User Manual"),
    ]

    for passed, message in file_checks:
        print(f"   {message}")
        if not passed:
            warnings.append(message)

    # ========================================
    # 3. Check Python Dependencies
    # ========================================
    print("\n🐍 Checking Python Dependencies...")

    package_checks = [
        check_python_package("anthropic"),
        check_python_package("github"),
        check_python_package("feedparser"),
    ]

    for passed, message in package_checks:
        print(f"   {message}")
        if not passed:
            warnings.append(message)

    # ========================================
    # 4. Check Optional Configuration
    # ========================================
    print("\n⚙️  Checking Optional Configuration...")

    optional_checks = [
        check_file("config/ideal-customer-profile.yaml", "ICP Configuration"),
        check_file(".repo-index/components.yaml", "Component Index"),
        check_file("docs/KNOWN_ISSUES.md", "Known Issues Documentation"),
    ]

    for passed, message in optional_checks:
        print(f"   {message}")
        if not passed and "Component Index" in message:
            print("      Note: Component index requires manual maintenance. See docs/KNOWN_ISSUES.md")

    # ========================================
    # 5. Summary
    # ========================================
    print("\n" + "=" * 60)

    if all_checks_passed and len(warnings) == 0:
        print("✅ All checks passed! Your factory is ready to operate.")
        print("\n🚀 Next Steps:")
        print("   1. Run 'gh workflow run hunter-loop.yml' to start trend hunting")
        print("   2. Monitor the Growth Engine (runs automatically every 6 hours)")
        print("   3. Review the User Manual at docs/USER_MANUAL.md")
        print("   4. Check docs/KNOWN_ISSUES.md for current limitations")
        return 0

    elif all_checks_passed and len(warnings) > 0:
        print("⚠️  Required secrets are configured, but there are warnings:")
        print(f"   {len(warnings)} non-critical issues detected")
        print("\n🔧 Suggested Actions:")
        print("   - Install missing Python packages: pip install -r requirements.txt")
        print("   - Verify file paths if any files are missing")
        return 0

    else:
        print("❌ Setup verification FAILED")
        print(f"   {len([c for c in checks if not c[0]])} critical issues detected")
        print("\n🛠️  Required Actions:")

        if not os.getenv('ANTHROPIC_API_KEY'):
            print("   1. Add ANTHROPIC_API_KEY secret:")
            print("      - Visit https://console.anthropic.com/")
            print("      - Create an API key")
            print("      - Add to Settings → Secrets → Actions")

        if not os.getenv('FACTORY_ADMIN_TOKEN'):
            print("   2. Add FACTORY_ADMIN_TOKEN secret:")
            print("      - Visit https://github.com/settings/tokens")
            print("      - Generate token with 'repo' and 'workflow' scopes")
            print("      - Add to Settings → Secrets → Actions")

        print("\n📚 For detailed setup instructions, see:")
        print("   - docs/USER_MANUAL.md")
        print("   - CLAUDE.md")
        print("   - docs/KNOWN_ISSUES.md")

        return 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n\n⚠️  Verification interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
