#!/usr/bin/env python3
"""
Conflict Detection Engine (Production Ready)
compares source and target directories to identify drift.

Features:
- Binary-safe comparison (filecmp)
- JSON reporting for CI/CD pipelines
- Human-readable CLI output
- Exit codes for pipeline control
"""

import os
import sys
import json
import argparse
import filecmp
import shutil
from pathlib import Path
from typing import Dict, List, Set, Union
from datetime import datetime

# --- Configuration ---
DEFAULT_IGNORE = [
    '.git', '.DS_Store', '__pycache__', 'node_modules', 
    'venv', '.env', 'dist', 'build', '.idea', '.vscode'
]

class ConflictDetector:
    def __init__(self, source: Path, target: Path, ignore_patterns: List[str] = None):
        self.source = source.resolve()
        self.target = target.resolve()
        self.ignore_patterns = set(ignore_patterns or DEFAULT_IGNORE)
        self.report = {
            "timestamp": datetime.now().isoformat(),
            "status": "clean",
            "summary": {
                "total_analyzed": 0,
                "unchanged": 0,
                "new": 0,
                "modified": 0,
                "deleted": 0
            },
            "files": {
                "new": [],
                "modified": [],
                "deleted": []
            }
        }

    def _should_ignore(self, path: Path) -> bool:
        """Check if a file or directory should be ignored."""
        for part in path.parts:
            if part in self.ignore_patterns:
                return True
        return False

    def _get_all_files(self, root_dir: Path) -> Set[str]:
        """Recursively get all relative file paths."""
        files = set()
        for root, dirs, filenames in os.walk(root_dir):
            # Modify dirs in-place to skip ignored directories during walk
            dirs[:] = [d for d in dirs if d not in self.ignore_patterns]
            
            for filename in filenames:
                if filename in self.ignore_patterns:
                    continue
                    
                full_path = Path(root) / filename
                rel_path = full_path.relative_to(root_dir)
                files.add(str(rel_path))
        return files

    def run(self):
        """Execute the comparison logic."""
        print(f"🔍 Analyzing drift...")
        print(f"   Source: {self.source}")
        print(f"   Target: {self.target}")

        source_files = self._get_all_files(self.source)
        target_files = self._get_all_files(self.target)
        all_files = source_files.union(target_files)

        self.report["summary"]["total_analyzed"] = len(all_files)

        for file_rel in sorted(all_files):
            src_file = self.source / file_rel
            tgt_file = self.target / file_rel

            # 1. New File (In Source, not Target)
            if file_rel in source_files and file_rel not in target_files:
                self.report["files"]["new"].append(file_rel)
                self.report["summary"]["new"] += 1
                continue

            # 2. Deleted File (In Target, not Source)
            if file_rel not in source_files and file_rel in target_files:
                self.report["files"]["deleted"].append(file_rel)
                self.report["summary"]["deleted"] += 1
                continue

            # 3. Compare Content (Both exist)
            # shallow=False forces reading file contents, not just stat signature
            if filecmp.cmp(src_file, tgt_file, shallow=False):
                self.report["summary"]["unchanged"] += 1
            else:
                self.report["files"]["modified"].append(file_rel)
                self.report["summary"]["modified"] += 1

        # Determine Final Status
        if (self.report["summary"]["new"] > 0 or 
            self.report["summary"]["modified"] > 0 or 
            self.report["summary"]["deleted"] > 0):
            self.report["status"] = "conflict"

    def print_summary(self):
        """Print a human-readable report."""
        s = self.report["summary"]
        print("\n📊 Drift Analysis Report")
        print("=" * 40)
        print(f"✅ Unchanged: {s['unchanged']}")
        
        if s['new'] > 0:
            print(f"✨ New Files: {s['new']}")
            for f in self.report["files"]["new"][:5]: print(f"   + {f}")
            if s['new'] > 5: print(f"   ...and {s['new']-5} more")
            
        if s['modified'] > 0:
            print(f"📝 Modified:  {s['modified']}")
            for f in self.report["files"]["modified"][:5]: print(f"   ~ {f}")
            if s['modified'] > 5: print(f"   ...and {s['modified']-5} more")

        if s['deleted'] > 0:
            print(f"🗑️  Deleted:   {s['deleted']}")
            for f in self.report["files"]["deleted"][:5]: print(f"   - {f}")
            if s['deleted'] > 5: print(f"   ...and {s['deleted']-5} more")

        print("=" * 40)
        print(f"Status: {self.report['status'].upper()}")

    def save_json(self, output_path: str):
        """Save report to JSON file."""
        with open(output_path, 'w') as f:
            json.dump(self.report, f, indent=2)

def main():
    parser = argparse.ArgumentParser(description="Autonomous Factory Conflict Detector")
    parser.add_argument("--source", required=True, help="Source directory")
    parser.add_argument("--target", required=True, help="Target directory")
    parser.add_argument("--output", default="conflicts.json", help="JSON report output path")
    parser.add_argument("--json-only", action="store_true", help="Suppress console output")
    parser.add_argument("--exit-on-conflict", action="store_true", help="Exit 1 if conflicts found")
    
    args = parser.parse_args()

    # Validation
    src = Path(args.source)
    tgt = Path(args.target)

    if not src.exists():
        if not args.json_only: print(f"❌ Error: Source path not found: {src}")
        sys.exit(1)
    if not tgt.exists():
        if not args.json_only: print(f"❌ Error: Target path not found: {tgt}")
        sys.exit(1)

    # Execution
    detector = ConflictDetector(src, tgt)
    detector.run()

    # Output
    if not args.json_only:
        detector.print_summary()
    
    detector.save_json(args.output)
    if not args.json_only:
        print(f"\nReport saved to: {args.output}")

    # Exit Codes
    if args.exit_on_conflict and detector.report["status"] == "conflict":
        sys.exit(1)
    
    sys.exit(0)

if __name__ == "__main__":
    main()
