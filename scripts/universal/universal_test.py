#!/usr/bin/env python3
"""
Universal Test Runner Script

This script runs tests for any repository based on detected or configured
tech stack. It accepts dynamic configuration inputs.

Usage:
    python scripts/universal/universal_test.py [--config CONFIG_FILE] [--coverage]

Configuration: Reads from config file or auto-detects tech stack
"""

import os
import sys
import json
import argparse
import subprocess
from pathlib import Path
from typing import Dict, Optional


def load_config(config_path: Optional[Path]) -> Dict[str, any]:
    """
    Load configuration from file if provided.

    Args:
        config_path: Path to config file (YAML or JSON)

    Returns:
        Configuration dictionary
    """
    if not config_path or not config_path.exists():
        return {}

    try:
        with open(config_path) as f:
            if config_path.suffix in ['.yaml', '.yml']:
                import yaml
                return yaml.safe_load(f)
            else:
                return json.load(f)
    except Exception as e:
        print(f"Warning: Could not load config file: {e}", file=sys.stderr)
        return {}


def detect_test_command(repo_path: Path) -> Optional[str]:
    """
    Auto-detect test command by running tech stack detection.

    Args:
        repo_path: Path to repository root

    Returns:
        Test command or None
    """
    detect_script = repo_path / 'scripts' / 'universal' / 'detect_tech_stack.py'

    if not detect_script.exists():
        return None

    try:
        result = subprocess.run(
            [sys.executable, str(detect_script), '--path', str(repo_path)],
            capture_output=True,
            text=True,
            check=True
        )

        tech_info = json.loads(result.stdout)
        return tech_info.get('test', {}).get('command')

    except Exception as e:
        print(f"Warning: Could not auto-detect test command: {e}", file=sys.stderr)
        return None


def run_tests(test_command: str, coverage: bool = False, repo_path: Path = Path('.')) -> int:
    """
    Run tests using the specified command.

    Args:
        test_command: Command to run tests
        coverage: Whether to enable coverage reporting
        repo_path: Path to repository root

    Returns:
        Exit code (0 = success, non-zero = failure)
    """
    if not test_command:
        print("Error: No test command specified or detected", file=sys.stderr)
        return 1

    # Modify command for coverage if requested
    if coverage:
        if 'pytest' in test_command:
            test_command = f"{test_command} --cov --cov-report=html --cov-report=term"
        elif 'npm' in test_command or 'yarn' in test_command:
            test_command = test_command.replace('test', 'test -- --coverage')
        elif 'flutter test' in test_command:
            test_command = f"{test_command} --coverage"
        elif 'go test' in test_command:
            test_command = f"{test_command} -cover"
        elif 'cargo test' in test_command:
            test_command = "cargo tarpaulin"

    print(f"🧪 Running tests: {test_command}")
    print("=" * 50)

    try:
        result = subprocess.run(
            test_command,
            shell=True,
            cwd=repo_path,
            check=False
        )

        if result.returncode == 0:
            print("\n" + "=" * 50)
            print("✅ All tests passed!")
        else:
            print("\n" + "=" * 50)
            print("❌ Tests failed!")

        return result.returncode

    except Exception as e:
        print(f"\n❌ Error running tests: {e}", file=sys.stderr)
        return 1


def main():
    """Main execution function."""
    parser = argparse.ArgumentParser(
        description='Universal test runner for any repository'
    )
    parser.add_argument(
        '--config',
        type=Path,
        help='Path to configuration file (optional)'
    )
    parser.add_argument(
        '--coverage',
        action='store_true',
        help='Enable coverage reporting'
    )
    parser.add_argument(
        '--command',
        help='Explicitly specify test command (overrides detection)'
    )
    parser.add_argument(
        '--path',
        type=Path,
        default=Path('.'),
        help='Path to repository root (default: current directory)'
    )

    args = parser.parse_args()
    repo_path = args.path.resolve()

    # Determine test command
    test_command = None

    # Priority 1: Explicit command
    if args.command:
        test_command = args.command
        print(f"📝 Using explicitly provided test command")

    # Priority 2: Config file
    elif args.config:
        config = load_config(args.config)
        test_command = config.get('tech_stack', {}).get('test', {}).get('command')
        if test_command:
            print(f"📝 Using test command from config file")

    # Priority 3: Auto-detection
    if not test_command:
        print("🔍 Auto-detecting test command...")
        test_command = detect_test_command(repo_path)
        if test_command:
            print(f"✓ Detected test command: {test_command}")

    # Run tests
    return run_tests(test_command, args.coverage, repo_path)


if __name__ == '__main__':
    sys.exit(main())
