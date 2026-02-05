#!/usr/bin/env python3
"""
Universal Build Script

This script builds any repository based on detected or configured
tech stack. It accepts dynamic configuration inputs.

Usage:
    python scripts/universal/universal_build.py [--config CONFIG_FILE] [--production]

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


def detect_build_command(repo_path: Path) -> Optional[str]:
    """
    Auto-detect build command by running tech stack detection.

    Args:
        repo_path: Path to repository root

    Returns:
        Build command or None
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
        return tech_info.get('build', {}).get('command')

    except Exception as e:
        print(f"Warning: Could not auto-detect build command: {e}", file=sys.stderr)
        return None


def run_build(build_command: str, production: bool = False, repo_path: Path = Path('.')) -> int:
    """
    Run build using the specified command.

    Args:
        build_command: Command to run build
        production: Whether to build for production
        repo_path: Path to repository root

    Returns:
        Exit code (0 = success, non-zero = failure)
    """
    if not build_command:
        print("Error: No build command specified or detected", file=sys.stderr)
        return 1

    # Modify command for production if requested
    if production:
        if 'flutter build' in build_command:
            build_command = f"{build_command} --release"
        elif 'cargo build' in build_command and '--release' not in build_command:
            build_command = f"{build_command} --release"
        elif 'npm run build' in build_command or 'yarn build' in build_command:
            # Set NODE_ENV for production
            os.environ['NODE_ENV'] = 'production'

    print(f"🔨 Running build: {build_command}")
    print("=" * 50)

    try:
        result = subprocess.run(
            build_command,
            shell=True,
            cwd=repo_path,
            check=False
        )

        if result.returncode == 0:
            print("\n" + "=" * 50)
            print("✅ Build completed successfully!")
        else:
            print("\n" + "=" * 50)
            print("❌ Build failed!")

        return result.returncode

    except Exception as e:
        print(f"\n❌ Error running build: {e}", file=sys.stderr)
        return 1


def main():
    """Main execution function."""
    parser = argparse.ArgumentParser(
        description='Universal build script for any repository'
    )
    parser.add_argument(
        '--config',
        type=Path,
        help='Path to configuration file (optional)'
    )
    parser.add_argument(
        '--production',
        action='store_true',
        help='Build for production'
    )
    parser.add_argument(
        '--command',
        help='Explicitly specify build command (overrides detection)'
    )
    parser.add_argument(
        '--path',
        type=Path,
        default=Path('.'),
        help='Path to repository root (default: current directory)'
    )

    args = parser.parse_args()
    repo_path = args.path.resolve()

    # Determine build command
    build_command = None

    # Priority 1: Explicit command
    if args.command:
        build_command = args.command
        print(f"📝 Using explicitly provided build command")

    # Priority 2: Config file
    elif args.config:
        config = load_config(args.config)
        build_command = config.get('tech_stack', {}).get('build', {}).get('command')
        if build_command:
            print(f"📝 Using build command from config file")

    # Priority 3: Auto-detection
    if not build_command:
        print("🔍 Auto-detecting build command...")
        build_command = detect_build_command(repo_path)
        if build_command:
            print(f"✓ Detected build command: {build_command}")

    # Run build
    return run_build(build_command, args.production, repo_path)


if __name__ == '__main__':
    sys.exit(main())
