#!/usr/bin/env python3
"""
Sync Manager Agent
Manages bidirectional sync relationships between factory and derived repos.

Features:
- Track derived repositories
- Monitor sync status
- Trigger automatic syncs
- Generate sync reports
"""

import os
import json
import yaml
import requests
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional


class SyncManager:
    def __init__(self, github_token: str, github_repo: str):
        self.github_token = github_token
        self.github_repo = github_repo
        self.manifest_path = Path(".repo-index/manifest.yaml")
        self.sync_status_path = Path(".repo-index/sync-status.json")

    def load_manifest(self) -> Dict:
        """Load the repository manifest."""
        if not self.manifest_path.exists():
            return {"components": [], "derived_repos": [], "last_updated": ""}

        with open(self.manifest_path, 'r') as f:
            return yaml.safe_load(f)

    def save_manifest(self, manifest: Dict):
        """Save the repository manifest."""
        self.manifest_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.manifest_path, 'w') as f:
            yaml.dump(manifest, f, default_flow_style=False, sort_keys=False)

    def register_derived_repo(self, repo_name: str, sync_paths: List[Dict]) -> bool:
        """
        Register a new derived repository for tracking.

        Args:
            repo_name: Full repository name (e.g., "owner/repo")
            sync_paths: List of sync path mappings
                        [{"source": "scripts/", "target": "scripts/", "strategy": "merge"}]

        Returns:
            bool: Success status
        """
        manifest = self.load_manifest()

        if "derived_repos" not in manifest:
            manifest["derived_repos"] = []

        # Check if repo already registered
        for repo in manifest["derived_repos"]:
            if repo["name"] == repo_name:
                print(f"⚠️  Repository {repo_name} already registered. Updating...")
                repo["sync_paths"] = sync_paths
                repo["last_updated"] = datetime.now().isoformat()
                self.save_manifest(manifest)
                return True

        # Add new repo
        manifest["derived_repos"].append({
            "name": repo_name,
            "registered_at": datetime.now().isoformat(),
            "last_updated": datetime.now().isoformat(),
            "last_sync": None,
            "sync_paths": sync_paths,
            "sync_enabled": True,
            "auto_sync": True
        })

        manifest["last_updated"] = datetime.now().isoformat()
        self.save_manifest(manifest)

        print(f"✅ Registered derived repository: {repo_name}")
        return True

    def unregister_derived_repo(self, repo_name: str) -> bool:
        """Remove a derived repository from tracking."""
        manifest = self.load_manifest()

        if "derived_repos" not in manifest:
            return False

        original_count = len(manifest["derived_repos"])
        manifest["derived_repos"] = [
            repo for repo in manifest["derived_repos"]
            if repo["name"] != repo_name
        ]

        if len(manifest["derived_repos"]) < original_count:
            manifest["last_updated"] = datetime.now().isoformat()
            self.save_manifest(manifest)
            print(f"✅ Unregistered repository: {repo_name}")
            return True

        print(f"⚠️  Repository {repo_name} not found")
        return False

    def list_derived_repos(self) -> List[Dict]:
        """Get list of all registered derived repositories."""
        manifest = self.load_manifest()
        return manifest.get("derived_repos", [])

    def get_repo_sync_status(self, repo_name: str) -> Optional[Dict]:
        """Get sync status for a specific repository."""
        repos = self.list_derived_repos()
        for repo in repos:
            if repo["name"] == repo_name:
                return repo
        return None

    def update_sync_status(self, repo_name: str, status: str, details: Dict = None):
        """
        Update sync status for a repository.

        Args:
            repo_name: Repository name
            status: "success", "failed", "in_progress"
            details: Additional details (conflicts, files changed, etc.)
        """
        manifest = self.load_manifest()

        if "derived_repos" not in manifest:
            return

        for repo in manifest["derived_repos"]:
            if repo["name"] == repo_name:
                repo["last_sync"] = datetime.now().isoformat()
                repo["last_sync_status"] = status
                if details:
                    repo["last_sync_details"] = details
                break

        manifest["last_updated"] = datetime.now().isoformat()
        self.save_manifest(manifest)

    def trigger_sync_workflow(self, repo_name: str, sync_path: str) -> bool:
        """
        Trigger the bidirectional-sync workflow for a specific repository.

        Args:
            repo_name: Target repository name
            sync_path: Sync path mapping (e.g., "scripts/:scripts/")

        Returns:
            bool: Success status
        """
        if not self.github_token:
            print("❌ No GitHub token available")
            return False

        url = f"https://api.github.com/repos/{self.github_repo}/actions/workflows/bidirectional-sync.yml/dispatches"
        headers = {
            "Authorization": f"token {self.github_token}",
            "Accept": "application/vnd.github.v3+json"
        }
        data = {
            "ref": "main",
            "inputs": {
                "target_repo": repo_name,
                "sync_path": sync_path
            }
        }

        try:
            response = requests.post(url, headers=headers, json=data)
            if response.status_code == 204:
                print(f"✅ Triggered sync workflow for {repo_name}")
                self.update_sync_status(repo_name, "in_progress")
                return True
            else:
                print(f"❌ Failed to trigger workflow: {response.status_code}")
                print(response.text)
                return False
        except Exception as e:
            print(f"❌ Error triggering workflow: {e}")
            return False

    def sync_all_enabled_repos(self):
        """Trigger sync for all repositories with auto_sync enabled."""
        repos = self.list_derived_repos()
        enabled_repos = [r for r in repos if r.get("auto_sync", False) and r.get("sync_enabled", False)]

        if not enabled_repos:
            print("ℹ️  No repositories configured for auto-sync")
            return

        print(f"🔄 Syncing {len(enabled_repos)} repositories...")

        for repo in enabled_repos:
            for sync_path in repo.get("sync_paths", []):
                path_mapping = f"{sync_path['source']}:{sync_path['target']}"
                print(f"  → {repo['name']} ({path_mapping})")
                self.trigger_sync_workflow(repo['name'], path_mapping)

    def generate_sync_report(self) -> str:
        """Generate a markdown report of sync status."""
        repos = self.list_derived_repos()

        if not repos:
            return "# Sync Status Report\n\nNo derived repositories registered.\n"

        report = "# Sync Status Report\n\n"
        report += f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}\n\n"
        report += f"**Total Repositories:** {len(repos)}\n\n"

        # Summary
        enabled_count = len([r for r in repos if r.get("sync_enabled", False)])
        auto_sync_count = len([r for r in repos if r.get("auto_sync", False)])

        report += "## Summary\n\n"
        report += f"- ✅ Enabled: {enabled_count}/{len(repos)}\n"
        report += f"- 🤖 Auto-sync: {auto_sync_count}/{len(repos)}\n\n"

        # Individual repos
        report += "## Repositories\n\n"

        for repo in repos:
            report += f"### {repo['name']}\n\n"
            report += f"- **Status:** {'✅ Enabled' if repo.get('sync_enabled') else '❌ Disabled'}\n"
            report += f"- **Auto-sync:** {'✅ Yes' if repo.get('auto_sync') else '❌ No'}\n"
            report += f"- **Registered:** {repo.get('registered_at', 'Unknown')}\n"

            if repo.get('last_sync'):
                status_emoji = {"success": "✅", "failed": "❌", "in_progress": "🔄"}.get(
                    repo.get('last_sync_status', ''), '❓'
                )
                report += f"- **Last Sync:** {repo['last_sync']} {status_emoji} {repo.get('last_sync_status', 'Unknown')}\n"
            else:
                report += f"- **Last Sync:** Never\n"

            # Sync paths
            report += f"- **Sync Paths:**\n"
            for path in repo.get('sync_paths', []):
                report += f"  - `{path['source']}` → `{path['target']}` ({path.get('strategy', 'merge')})\n"

            report += "\n"

        return report


def main():
    """CLI interface for sync manager."""
    import argparse

    parser = argparse.ArgumentParser(description="Factory Sync Manager")
    parser.add_argument("command", choices=[
        "register", "unregister", "list", "status", "sync", "sync-all", "report"
    ])
    parser.add_argument("--repo", help="Repository name (owner/repo)")
    parser.add_argument("--sync-paths", help="Sync paths JSON")
    parser.add_argument("--sync-path", help="Single sync path (source:target)")

    args = parser.parse_args()

    github_token = os.getenv("GITHUB_TOKEN", "")
    github_repo = os.getenv("GITHUB_REPOSITORY", "")

    manager = SyncManager(github_token, github_repo)

    if args.command == "register":
        if not args.repo or not args.sync_paths:
            print("❌ --repo and --sync-paths required for register")
            return 1

        sync_paths = json.loads(args.sync_paths)
        manager.register_derived_repo(args.repo, sync_paths)

    elif args.command == "unregister":
        if not args.repo:
            print("❌ --repo required for unregister")
            return 1
        manager.unregister_derived_repo(args.repo)

    elif args.command == "list":
        repos = manager.list_derived_repos()
        print(f"\n📋 Registered Repositories ({len(repos)}):\n")
        for repo in repos:
            status = "✅" if repo.get("sync_enabled") else "❌"
            print(f"{status} {repo['name']}")

    elif args.command == "status":
        if not args.repo:
            print("❌ --repo required for status")
            return 1
        status = manager.get_repo_sync_status(args.repo)
        if status:
            print(json.dumps(status, indent=2))
        else:
            print(f"❌ Repository {args.repo} not found")

    elif args.command == "sync":
        if not args.repo or not args.sync_path:
            print("❌ --repo and --sync-path required for sync")
            return 1
        manager.trigger_sync_workflow(args.repo, args.sync_path)

    elif args.command == "sync-all":
        manager.sync_all_enabled_repos()

    elif args.command == "report":
        report = manager.generate_sync_report()
        print(report)

        # Save to file
        report_path = Path(".repo-index/sync-report.md")
        report_path.write_text(report)
        print(f"\n📄 Report saved to {report_path}")

    return 0


if __name__ == "__main__":
    exit(main())
