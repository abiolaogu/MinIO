#!/usr/bin/env python3
"""
Universal Tech Stack Detection Script

This script detects the technology stack of any repository by analyzing
project files and configuration. It outputs structured data that other
scripts and workflows can consume.

Usage:
    python scripts/universal/detect_tech_stack.py [--path PATH] [--format json|yaml]

Configuration: None required - fully dynamic detection
"""

import os
import sys
import json
import argparse
from pathlib import Path
from typing import Dict, List, Optional


def detect_package_manager(repo_path: Path) -> Optional[str]:
    """
    Detect package manager based on lock files and config files.

    Args:
        repo_path: Path to repository root

    Returns:
        Package manager name or None
    """
    indicators = {
        'npm': ['package-lock.json', 'npm-shrinkwrap.json'],
        'yarn': ['yarn.lock'],
        'pnpm': ['pnpm-lock.yaml'],
        'pip': ['requirements.txt', 'Pipfile', 'setup.py', 'pyproject.toml'],
        'poetry': ['poetry.lock'],
        'cargo': ['Cargo.lock', 'Cargo.toml'],
        'go': ['go.mod', 'go.sum'],
        'pub': ['pubspec.lock'],
        'bundle': ['Gemfile.lock'],
        'maven': ['pom.xml'],
        'gradle': ['build.gradle', 'build.gradle.kts'],
    }

    for manager, files in indicators.items():
        for file in files:
            if (repo_path / file).exists():
                return manager

    return None


def detect_language(repo_path: Path) -> Dict[str, any]:
    """
    Detect primary programming language and related information.

    Args:
        repo_path: Path to repository root

    Returns:
        Dictionary with language information
    """
    language_indicators = [
        # Format: (file_pattern, language, framework_hint)
        ('pubspec.yaml', 'dart', 'flutter'),
        ('requirements.txt', 'python', None),
        ('Pipfile', 'python', None),
        ('pyproject.toml', 'python', None),
        ('package.json', 'javascript', None),
        ('Cargo.toml', 'rust', None),
        ('go.mod', 'go', None),
        ('Gemfile', 'ruby', None),
        ('pom.xml', 'java', None),
        ('build.gradle', 'java', None),
        ('*.csproj', 'csharp', None),
        ('*.fsproj', 'fsharp', None),
    ]

    for pattern, language, framework_hint in language_indicators:
        if '*' in pattern:
            # Glob pattern
            if list(repo_path.glob(pattern)):
                return {
                    'language': language,
                    'framework': framework_hint,
                    'detected_via': pattern
                }
        else:
            # Exact file
            if (repo_path / pattern).exists():
                return {
                    'language': language,
                    'framework': framework_hint,
                    'detected_via': pattern
                }

    return {
        'language': 'unknown',
        'framework': None,
        'detected_via': None
    }


def detect_framework(repo_path: Path, language: str) -> Optional[str]:
    """
    Detect specific framework based on language and project files.

    Args:
        repo_path: Path to repository root
        language: Detected programming language

    Returns:
        Framework name or None
    """
    framework_indicators = {
        'javascript': {
            'react': ['react', '@types/react'],
            'vue': ['vue', '@vue/cli'],
            'angular': ['@angular/core'],
            'express': ['express'],
            'next': ['next'],
            'nuxt': ['nuxt'],
            'svelte': ['svelte'],
        },
        'python': {
            'django': ['django'],
            'flask': ['flask'],
            'fastapi': ['fastapi'],
            'pyramid': ['pyramid'],
        },
        'dart': {
            'flutter': ['flutter'],
        },
        'ruby': {
            'rails': ['rails'],
        },
    }

    # Check package.json dependencies
    package_json = repo_path / 'package.json'
    if package_json.exists() and language == 'javascript':
        try:
            with open(package_json) as f:
                data = json.load(f)
                dependencies = {**data.get('dependencies', {}), **data.get('devDependencies', {})}

                for framework, indicators in framework_indicators.get('javascript', {}).items():
                    if any(indicator in dependencies for indicator in indicators):
                        return framework
        except:
            pass

    # Check requirements.txt
    requirements = repo_path / 'requirements.txt'
    if requirements.exists() and language == 'python':
        try:
            with open(requirements) as f:
                content = f.read().lower()

                for framework, indicators in framework_indicators.get('python', {}).items():
                    if any(indicator in content for indicator in indicators):
                        return framework
        except:
            pass

    # Check pubspec.yaml
    pubspec = repo_path / 'pubspec.yaml'
    if pubspec.exists() and language == 'dart':
        return 'flutter'

    return None


def detect_build_system(repo_path: Path, language: str, package_manager: Optional[str]) -> Dict[str, any]:
    """
    Detect build system and common build commands.

    Args:
        repo_path: Path to repository root
        language: Detected programming language
        package_manager: Detected package manager

    Returns:
        Dictionary with build system information
    """
    build_info = {
        'enabled': False,
        'command': None,
        'output_dir': None,
    }

    # Check for common build scripts in package.json
    package_json = repo_path / 'package.json'
    if package_json.exists():
        try:
            with open(package_json) as f:
                data = json.load(f)
                scripts = data.get('scripts', {})

                if 'build' in scripts:
                    build_info['enabled'] = True
                    build_info['command'] = f'{package_manager} run build' if package_manager else 'npm run build'
                    build_info['output_dir'] = 'dist'  # Common default
        except:
            pass

    # Flutter
    if language == 'dart':
        build_info['enabled'] = True
        build_info['command'] = 'flutter build'
        build_info['output_dir'] = 'build'

    # Python with setup.py
    if language == 'python' and (repo_path / 'setup.py').exists():
        build_info['enabled'] = True
        build_info['command'] = 'python setup.py build'
        build_info['output_dir'] = 'build'

    # Go
    if language == 'go':
        build_info['enabled'] = True
        build_info['command'] = 'go build'
        build_info['output_dir'] = '.'

    # Rust
    if language == 'rust':
        build_info['enabled'] = True
        build_info['command'] = 'cargo build --release'
        build_info['output_dir'] = 'target/release'

    return build_info


def detect_test_system(repo_path: Path, language: str, package_manager: Optional[str]) -> Dict[str, any]:
    """
    Detect test system and common test commands.

    Args:
        repo_path: Path to repository root
        language: Detected programming language
        package_manager: Detected package manager

    Returns:
        Dictionary with test system information
    """
    test_info = {
        'enabled': False,
        'command': None,
        'coverage_enabled': False,
    }

    # Check for test directory
    tests_exist = (repo_path / 'tests').exists() or (repo_path / 'test').exists()

    # Check package.json scripts
    package_json = repo_path / 'package.json'
    if package_json.exists():
        try:
            with open(package_json) as f:
                data = json.load(f)
                scripts = data.get('scripts', {})

                if 'test' in scripts:
                    test_info['enabled'] = True
                    test_info['command'] = f'{package_manager} test' if package_manager else 'npm test'
                    test_info['coverage_enabled'] = 'coverage' in scripts
        except:
            pass

    # Python
    if language == 'python' and tests_exist:
        test_info['enabled'] = True
        # Check for pytest
        requirements = repo_path / 'requirements.txt'
        if requirements.exists():
            try:
                with open(requirements) as f:
                    if 'pytest' in f.read().lower():
                        test_info['command'] = 'pytest'
                        test_info['coverage_enabled'] = True
            except:
                pass

        if not test_info['command']:
            test_info['command'] = 'python -m unittest discover'

    # Flutter/Dart
    if language == 'dart':
        test_info['enabled'] = True
        test_info['command'] = 'flutter test'

    # Go
    if language == 'go':
        test_info['enabled'] = True
        test_info['command'] = 'go test ./...'

    # Rust
    if language == 'rust':
        test_info['enabled'] = True
        test_info['command'] = 'cargo test'

    return test_info


def detect_lint_system(repo_path: Path, language: str, package_manager: Optional[str]) -> Dict[str, any]:
    """
    Detect linting system and commands.

    Args:
        repo_path: Path to repository root
        language: Detected programming language
        package_manager: Detected package manager

    Returns:
        Dictionary with lint system information
    """
    lint_info = {
        'enabled': False,
        'command': None,
    }

    # Check package.json scripts
    package_json = repo_path / 'package.json'
    if package_json.exists():
        try:
            with open(package_json) as f:
                data = json.load(f)
                scripts = data.get('scripts', {})
                dependencies = {**data.get('dependencies', {}), **data.get('devDependencies', {})}

                if 'lint' in scripts:
                    lint_info['enabled'] = True
                    lint_info['command'] = f'{package_manager} run lint' if package_manager else 'npm run lint'
                elif 'eslint' in dependencies:
                    lint_info['enabled'] = True
                    lint_info['command'] = 'eslint .'
        except:
            pass

    # Python
    if language == 'python':
        # Check for common linters
        linters = [
            ('pylint', 'pylint src'),
            ('flake8', 'flake8 src'),
            ('black', 'black --check src'),
            ('ruff', 'ruff check .'),
        ]

        requirements = repo_path / 'requirements.txt'
        if requirements.exists():
            try:
                with open(requirements) as f:
                    content = f.read().lower()

                    for linter, command in linters:
                        if linter in content:
                            lint_info['enabled'] = True
                            lint_info['command'] = command
                            break
            except:
                pass

    # Flutter/Dart
    if language == 'dart':
        lint_info['enabled'] = True
        lint_info['command'] = 'flutter analyze'

    # Go
    if language == 'go':
        lint_info['enabled'] = True
        lint_info['command'] = 'go vet ./...'

    # Rust
    if language == 'rust':
        lint_info['enabled'] = True
        lint_info['command'] = 'cargo clippy'

    return lint_info


def detect_tech_stack(repo_path: Path) -> Dict[str, any]:
    """
    Main function to detect complete tech stack.

    Args:
        repo_path: Path to repository root

    Returns:
        Complete tech stack information
    """
    language_info = detect_language(repo_path)
    language = language_info['language']

    package_manager = detect_package_manager(repo_path)
    framework = detect_framework(repo_path, language) or language_info['framework']

    build_info = detect_build_system(repo_path, language, package_manager)
    test_info = detect_test_system(repo_path, language, package_manager)
    lint_info = detect_lint_system(repo_path, language, package_manager)

    return {
        'tech_stack': {
            'primary_language': language,
            'framework': framework,
            'package_manager': package_manager,
            'detected_via': language_info['detected_via'],
        },
        'build': build_info,
        'test': test_info,
        'lint': lint_info,
    }


def main():
    """Main execution function."""
    parser = argparse.ArgumentParser(
        description='Detect technology stack of any repository'
    )
    parser.add_argument(
        '--path',
        default='.',
        help='Path to repository root (default: current directory)'
    )
    parser.add_argument(
        '--format',
        choices=['json', 'yaml'],
        default='json',
        help='Output format (default: json)'
    )

    args = parser.parse_args()
    repo_path = Path(args.path).resolve()

    if not repo_path.exists():
        print(f"Error: Path does not exist: {repo_path}", file=sys.stderr)
        return 1

    # Detect tech stack
    result = detect_tech_stack(repo_path)

    # Output in requested format
    if args.format == 'json':
        print(json.dumps(result, indent=2))
    elif args.format == 'yaml':
        try:
            import yaml
            print(yaml.dump(result, default_flow_style=False))
        except ImportError:
            print("Error: PyYAML not installed. Install with: pip install pyyaml", file=sys.stderr)
            print("\nFalling back to JSON output:")
            print(json.dumps(result, indent=2))

    return 0


if __name__ == '__main__':
    sys.exit(main())
