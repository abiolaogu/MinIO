# Universal Scripts

This directory contains language-agnostic scripts that work with any repository through dynamic detection and configuration.

## Scripts

### `detect_tech_stack.py`
Automatically detects programming language, framework, package manager, and tooling for any repository.

**Usage**: `python detect_tech_stack.py [--path PATH] [--format json|yaml]`

### `universal_test.py`
Runs tests for any repository using detected or configured test framework.

**Usage**: `python universal_test.py [--config CONFIG] [--coverage] [--command CMD]`

### `universal_build.py`
Builds any repository using detected or configured build system.

**Usage**: `python universal_build.py [--config CONFIG] [--production] [--command CMD]`

### `universal_lint.py`
Runs linting for any repository using detected or configured linter.

**Usage**: `python universal_lint.py [--config CONFIG] [--fix] [--command CMD]`

## Key Features

- **Zero Configuration**: Auto-detects tech stack and runs appropriate commands
- **Fully Configurable**: Accepts explicit configuration when needed
- **No Hardcoded Values**: Works with any project structure
- **Language Agnostic**: Supports Python, JavaScript, Dart, Go, Rust, Ruby, Java, C#

## Configuration Priority

1. Explicit `--command` flag (highest)
2. Configuration file via `--config`
3. Auto-detection (lowest)

## Examples

```bash
# Detect tech stack
python detect_tech_stack.py

# Run tests with auto-detection
python universal_test.py

# Build with explicit command
python universal_build.py --command "npm run build"

# Lint with config file
python universal_lint.py --config config.yaml
```

See [full documentation](../../docs/universal-transformation-kit.md) for detailed usage.
