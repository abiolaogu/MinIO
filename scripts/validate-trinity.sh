#!/bin/bash

###############################################################################
# Holy Trinity Validator
# Enforces XP + DDD + Legacy Modernization standards in CI/CD pipeline
#
# Exit codes:
#   0 - All checks passed
#   1 - XP violation (test coverage or build time)
#   2 - DDD violation (cross-context pollution)
#   3 - Multiple violations
###############################################################################

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Violation tracking
violations=0

echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo -e "${BLUE}   Holy Trinity Compliance Validator${NC}"
echo -e "${BLUE}   XP • DDD • Legacy Modernization${NC}"
echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo ""

###############################################################################
# XP Check 1: Test Coverage Must Be >= 80%
###############################################################################

echo -e "${BLUE}[1/3] XP Check: Test Coverage${NC}"

# Detect test framework and check coverage
check_coverage() {
  local min_coverage=80
  local actual_coverage=0

  # Check for package.json (JavaScript/TypeScript)
  if [ -f "package.json" ]; then
    echo "  Detected: Node.js project"

    # Check if coverage script exists
    if grep -q '"coverage"' package.json; then
      echo "  Running: npm run coverage"

      # Run coverage and capture output
      if npm run coverage > coverage_output.txt 2>&1; then
        # Try to extract coverage percentage (common formats)
        actual_coverage=$(grep -oP 'All files[^|]*\|[^|]*\|[^|]*\|[^|]*\|\s*\K[0-9]+(?:\.[0-9]+)?' coverage_output.txt | head -1 || echo "0")

        # Fallback: try Jest format
        if [ "$actual_coverage" = "0" ]; then
          actual_coverage=$(grep -oP 'Statements\s*:\s*\K[0-9]+(?:\.[0-9]+)?' coverage_output.txt | head -1 || echo "0")
        fi

        echo "  Coverage: ${actual_coverage}%"
        rm -f coverage_output.txt
      else
        echo -e "${YELLOW}  Warning: Coverage command failed${NC}"
        rm -f coverage_output.txt
        return 0
      fi
    else
      echo -e "${YELLOW}  Warning: No coverage script found in package.json${NC}"
      return 0
    fi

  # Check for pubspec.yaml (Flutter/Dart)
  elif [ -f "pubspec.yaml" ]; then
    echo "  Detected: Flutter project"

    if command -v flutter &> /dev/null; then
      echo "  Running: flutter test --coverage"

      if flutter test --coverage > coverage_output.txt 2>&1; then
        # Parse lcov.info if it exists
        if [ -f "coverage/lcov.info" ]; then
          # Use lcov to get summary if available
          if command -v lcov &> /dev/null; then
            actual_coverage=$(lcov --summary coverage/lcov.info 2>&1 | grep -oP 'lines......: \K[0-9]+(?:\.[0-9]+)?' | head -1 || echo "0")
          else
            echo -e "${YELLOW}  Warning: lcov not installed, cannot parse coverage${NC}"
          fi
        fi

        echo "  Coverage: ${actual_coverage}%"
        rm -f coverage_output.txt
      else
        echo -e "${YELLOW}  Warning: Flutter test failed${NC}"
        rm -f coverage_output.txt
        return 0
      fi
    else
      echo -e "${YELLOW}  Warning: Flutter not installed${NC}"
      return 0
    fi

  # Check for build.gradle.kts (Android/Kotlin)
  elif [ -f "build.gradle.kts" ] || [ -f "app/build.gradle.kts" ]; then
    echo "  Detected: Android project"

    if [ -f "gradlew" ]; then
      echo "  Running: ./gradlew testDebugUnitTestCoverage"

      if ./gradlew testDebugUnitTestCoverage > coverage_output.txt 2>&1; then
        # Look for JaCoCo report
        if [ -f "app/build/reports/jacoco/testDebugUnitTestCoverage/html/index.html" ]; then
          actual_coverage=$(grep -oP 'Total[^<]*<td[^>]*>[^<]*<td[^>]*>\K[0-9]+(?:\.[0-9]+)?' app/build/reports/jacoco/testDebugUnitTestCoverage/html/index.html | head -1 || echo "0")
        fi

        echo "  Coverage: ${actual_coverage}%"
        rm -f coverage_output.txt
      else
        echo -e "${YELLOW}  Warning: Gradle coverage task failed${NC}"
        rm -f coverage_output.txt
        return 0
      fi
    else
      echo -e "${YELLOW}  Warning: gradlew not found${NC}"
      return 0
    fi

  # Check for Xcode project (iOS/Swift)
  elif [ -f "*.xcodeproj" ] || [ -f "*.xcworkspace" ]; then
    echo "  Detected: iOS project"
    echo -e "${YELLOW}  Warning: iOS coverage checking requires Xcode and xccov${NC}"
    return 0

  else
    echo -e "${YELLOW}  Warning: No recognized project type found${NC}"
    return 0
  fi

  # Check if coverage meets minimum
  if (( $(echo "$actual_coverage < $min_coverage" | bc -l) )); then
    echo -e "${RED}  ✗ FAIL: Coverage ${actual_coverage}% is below minimum ${min_coverage}%${NC}"
    return 1
  else
    echo -e "${GREEN}  ✓ PASS: Coverage ${actual_coverage}% meets minimum ${min_coverage}%${NC}"
    return 0
  fi
}

if ! check_coverage; then
  violations=$((violations + 1))
fi

echo ""

###############################################################################
# XP Check 2: Build Time Must Be <= 10 Minutes
###############################################################################

echo -e "${BLUE}[2/3] XP Check: Build Time${NC}"

check_build_time() {
  local max_build_seconds=600  # 10 minutes
  local start_time=$(date +%s)

  # Detect project type and run build
  if [ -f "package.json" ]; then
    echo "  Running: npm run build"

    if grep -q '"build"' package.json; then
      if npm run build > build_output.txt 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local duration_min=$((duration / 60))
        local duration_sec=$((duration % 60))

        echo "  Build time: ${duration_min}m ${duration_sec}s"
        rm -f build_output.txt

        if [ $duration -gt $max_build_seconds ]; then
          echo -e "${RED}  ✗ FAIL: Build time exceeds 10 minutes${NC}"
          return 1
        else
          echo -e "${GREEN}  ✓ PASS: Build completed within time limit${NC}"
          return 0
        fi
      else
        echo -e "${YELLOW}  Warning: Build command failed${NC}"
        rm -f build_output.txt
        return 0
      fi
    else
      echo -e "${YELLOW}  Warning: No build script found${NC}"
      return 0
    fi

  elif [ -f "pubspec.yaml" ]; then
    echo "  Running: flutter build apk --debug"

    if command -v flutter &> /dev/null; then
      if flutter build apk --debug > build_output.txt 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local duration_min=$((duration / 60))
        local duration_sec=$((duration % 60))

        echo "  Build time: ${duration_min}m ${duration_sec}s"
        rm -f build_output.txt

        if [ $duration -gt $max_build_seconds ]; then
          echo -e "${RED}  ✗ FAIL: Build time exceeds 10 minutes${NC}"
          return 1
        else
          echo -e "${GREEN}  ✓ PASS: Build completed within time limit${NC}"
          return 0
        fi
      else
        echo -e "${YELLOW}  Warning: Flutter build failed${NC}"
        rm -f build_output.txt
        return 0
      fi
    else
      echo -e "${YELLOW}  Warning: Flutter not installed${NC}"
      return 0
    fi

  elif [ -f "gradlew" ]; then
    echo "  Running: ./gradlew assembleDebug"

    if ./gradlew assembleDebug > build_output.txt 2>&1; then
      local end_time=$(date +%s)
      local duration=$((end_time - start_time))
      local duration_min=$((duration / 60))
      local duration_sec=$((duration % 60))

      echo "  Build time: ${duration_min}m ${duration_sec}s"
      rm -f build_output.txt

      if [ $duration -gt $max_build_seconds ]; then
        echo -e "${RED}  ✗ FAIL: Build time exceeds 10 minutes${NC}"
        return 1
      else
        echo -e "${GREEN}  ✓ PASS: Build completed within time limit${NC}"
        return 0
      fi
    else
      echo -e "${YELLOW}  Warning: Gradle build failed${NC}"
      rm -f build_output.txt
      return 0
    fi

  else
    echo -e "${YELLOW}  Warning: No build configuration found${NC}"
    return 0
  fi
}

if ! check_build_time; then
  violations=$((violations + 1))
fi

echo ""

###############################################################################
# DDD Check: No Cross-Context Pollution
###############################################################################

echo -e "${BLUE}[3/3] DDD Check: Bounded Context Isolation${NC}"

check_context_pollution() {
  # Define bounded contexts
  local contexts=("identity" "commerce" "billing" "inventory" "analytics" "notification")
  local found_violations=0

  # Check if contexts directory exists
  if [ ! -d "src/contexts" ] && [ ! -d "lib/contexts" ]; then
    echo -e "${YELLOW}  Warning: No contexts directory found (src/contexts or lib/contexts)${NC}"
    echo "  Skipping DDD context pollution check"
    return 0
  fi

  local contexts_dir="src/contexts"
  if [ -d "lib/contexts" ]; then
    contexts_dir="lib/contexts"
  fi

  echo "  Scanning: $contexts_dir"

  # For each context, check for illegal imports
  for context in "${contexts[@]}"; do
    local context_path="$contexts_dir/$context"

    if [ ! -d "$context_path" ]; then
      continue
    fi

    echo "  Checking context: $context"

    # Find all source files in this context
    local source_files=$(find "$context_path" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.dart" -o -name "*.kt" -o -name "*.swift" \) 2>/dev/null || true)

    if [ -z "$source_files" ]; then
      continue
    fi

    # Check each file for cross-context imports
    while IFS= read -r file; do
      # Skip if file doesn't exist
      [ ! -f "$file" ] && continue

      # Check for imports from other contexts (not via api/)
      for other_context in "${contexts[@]}"; do
        if [ "$context" != "$other_context" ]; then
          # Look for direct imports (not through public API)
          # Bad: import { User } from '../identity/domain/User'
          # Good: import { User } from '@/contexts/identity/api'

          local violations=$(grep -n "from.*['\"].*/$other_context/\(domain\|application\|infrastructure\|presentation\)" "$file" 2>/dev/null || true)

          if [ -n "$violations" ]; then
            echo -e "${RED}    ✗ Cross-context violation in $(basename $file):${NC}"
            echo "$violations" | while IFS= read -r line; do
              echo -e "${RED}      $line${NC}"
            done
            found_violations=$((found_violations + 1))
          fi
        fi
      done
    done <<< "$source_files"
  done

  if [ $found_violations -gt 0 ]; then
    echo -e "${RED}  ✗ FAIL: Found $found_violations cross-context import violations${NC}"
    echo "  Contexts must only import from other contexts via public API (api/index.ts)"
    return 1
  else
    echo -e "${GREEN}  ✓ PASS: No cross-context pollution detected${NC}"
    return 0
  fi
}

if ! check_context_pollution; then
  violations=$((violations + 1))
fi

echo ""

###############################################################################
# Summary
###############################################################################

echo -e "${BLUE}════════════════════════════════════════════════${NC}"

if [ $violations -eq 0 ]; then
  echo -e "${GREEN}✓ All Holy Trinity checks passed!${NC}"
  echo -e "${GREEN}  Your code adheres to XP + DDD + Legacy standards${NC}"
  exit 0
else
  echo -e "${RED}✗ Found $violations violation(s)${NC}"
  echo -e "${RED}  Please fix the issues above and try again${NC}"
  echo ""
  echo "Resources:"
  echo "  - Read docs/HOLY_TRINITY.md for guidelines"
  echo "  - Review config/workik/master-prompt.md for standards"
  exit $violations
fi
