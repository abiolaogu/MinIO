#!/usr/bin/env python3
"""
Universal Lint Script

This script runs linting for any repository based on detected or configured
tech stack. It accepts dynamic configuration inputs.

Usage:
    python scripts/universal/universal_lint.py [--config CONFIG_FILE] [--fix]

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


def detect_lint_command(repo_path: Path) -> Optional[str]:
    """
    Auto-detect lint command by running tech stack detection.

    Args:
        repo_path: Path to repository root

    Returns:
        Lint command or None
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
        return tech_info.get('lint', {}).get('command')

    except Exception as e:
        print(f"Warning: Could not auto-detect lint command: {e}", file=sys.stderr)
        return None


def run_lint(lint_command: str, fix: bool = False, repo_path: Path = Path('.')) -> int:
    """
    Run linting using the specified command.

    Args:
        lint_command: Command to run lint
        fix: Whether to auto-fix issues
        repo_path: Path to repository root

    Returns:
        Exit code (0 = success, non-zero = failure)
    """
    if not lint_command:
        print("Error: No lint command specified or detected", file=sys.stderr)
        return 1

    # Modify command for auto-fix if requested
    if fix:
        if 'eslint' in lint_command:
            lint_command = f"{lint_command} --fix"
        elif 'black' in lint_command:
            lint_command = lint_command.replace('--check', '')
        elif 'ruff' in lint_command:
            lint_command = f"{lint_command} --fix"
        elif 'cargo clippy' in lint_command:
            lint_command = f"{lint_command} --fix"

    print(f"🔍 Running lint: {lint_command}")
    print("=" * 50)

    try:
        result = subprocess.run(
            lint_command,
            shell=True,
            cwd=repo_path,
            check=False
        )

        if result.returncode == 0:
            print("\n" + "=" * 50)
            print("✅ Linting passed!")
        else:
            print("\n" + "=" * 50)
            print("❌ Linting found issues!")

        return result.returncode

    except Exception as e:
        print(f"\n❌ Error running lint: {e}", file=sys.stderr)
        return 1


def main():
    """Main execution function."""
    parser = argparse.ArgumentParser(
        description='Universal lint script for any repository'
    )
    parser.add_argument(
        '--config',
        type=Path,
        help='Path to configuration file (optional)'
    )
    parser.add_argument(
        '--fix',
        action='store_true',
        help='Automatically fix linting issues where possible'
    )
    parser.add_argument(
        '--command',
        help='Explicitly specify lint command (overrides detection)'
    )
    parser.add_argument(
        '--path',
        type=Path,
        default=Path('.'),
        help='Path to repository root (default: current directory)'
    )

    args = parser.parse_args()
    repo_path = args.path.resolve()

    # Determine lint command
    lint_command = None

    # Priority 1: Explicit command
    if args.command:
        lint_command = args.command
        print(f"📝 Using explicitly provided lint command")

    # Priority 2: Config file
    elif args.config:
        config = load_config(args.config)
        lint_command = config.get('tech_stack', {}).get('lint', {}).get('command')
        if lint_command:
            print(f"📝 Using lint command from config file")

    # Priority 3: Auto-detection
    if not lint_command:
        print("🔍 Auto-detecting lint command...")
        lint_command = detect_lint_command(repo_path)
        if lint_command:
            print(f"✓ Detected lint command: {lint_command}")

    # Run lint
    return run_lint(lint_command, args.fix, repo_path)


if __name__ == '__main__':
    sys.exit(main())
