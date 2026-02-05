#!/usr/bin/env python3
"""
Factory Remote Installation Script

This script installs the Factory Template autonomous system into a remote repository.
It clones the target repository, injects factory components, and pushes the upgrade.

Usage:
    python scripts/install_remote.py <target_repo_url>

Example:
    python scripts/install_remote.py https://github.com/abiolaogu/VoxGuard

Environment Variables Required:
    FACTORY_ADMIN_TOKEN: GitHub Personal Access Token with 'repo' and 'workflow' scopes
"""

import os
import sys
import shutil
import tempfile
import subprocess
from pathlib import Path
from typing import List, Tuple


class Colors:
    """ANSI color codes for terminal output"""
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'  # No Color


class FactoryInstaller:
    """Handles installation of Factory Template into remote repositories"""

    # Components to transplant (relative to factory root)
    FACTORY_COMPONENTS = [
        '.github/workflows',
        'scripts',
        'config',
        'CLAUDE.md',
        'requirements.txt',
    ]

    def __init__(self, target_repo_url: str):
        self.target_repo_url = target_repo_url.rstrip('/')
        self.factory_root = Path(__file__).parent.parent.absolute()
        self.temp_dir = None
        self.target_dir = None

        # Validate environment
        self.token = os.environ.get('FACTORY_ADMIN_TOKEN')
        if not self.token:
            raise EnvironmentError(
                f"{Colors.RED}ERROR: FACTORY_ADMIN_TOKEN environment variable not set{Colors.NC}\n"
                "Please set your GitHub Personal Access Token with 'repo' and 'workflow' scopes."
            )

    def _run_command(self, cmd: List[str], cwd: Path = None, check: bool = True) -> Tuple[int, str, str]:
        """Run a shell command and return exit code, stdout, stderr"""
        result = subprocess.run(
            cmd,
            cwd=cwd or self.factory_root,
            capture_output=True,
            text=True,
            check=False
        )

        if check and result.returncode != 0:
            raise RuntimeError(
                f"{Colors.RED}Command failed: {' '.join(cmd)}{Colors.NC}\n"
                f"Exit code: {result.returncode}\n"
                f"Error: {result.stderr}"
            )

        return result.returncode, result.stdout, result.stderr

    def _create_authenticated_url(self, repo_url: str) -> str:
        """Create an authenticated Git URL using the token"""
        # Handle both http and https URLs
        if repo_url.startswith('http://'):
            repo_url = repo_url.replace('http://', 'https://')

        # Extract the repo path after github.com
        if 'github.com/' in repo_url:
            repo_path = repo_url.split('github.com/')[-1]
            return f"https://{self.token}@github.com/{repo_path}"
        else:
            raise ValueError(f"Invalid GitHub URL: {repo_url}")

    def print_banner(self):
        """Print installation banner"""
        print(f"\n{Colors.BLUE}{'=' * 60}{Colors.NC}")
        print(f"{Colors.BLUE}  Factory Template Remote Installation{Colors.NC}")
        print(f"{Colors.BLUE}{'=' * 60}{Colors.NC}\n")
        print(f"{Colors.GREEN}Source:{Colors.NC} {self.factory_root}")
        print(f"{Colors.GREEN}Target:{Colors.NC} {self.target_repo_url}\n")

    def clone_target_repo(self):
        """Clone the target repository to a temporary directory"""
        print(f"{Colors.YELLOW}➤{Colors.NC} Cloning target repository...")

        # Create temporary directory
        self.temp_dir = tempfile.mkdtemp(prefix='factory_install_')
        self.target_dir = Path(self.temp_dir) / 'target_repo'

        # Create authenticated URL
        auth_url = self._create_authenticated_url(self.target_repo_url)

        # Clone the repository
        try:
            self._run_command([
                'git', 'clone',
                auth_url,
                str(self.target_dir)
            ])
            print(f"{Colors.GREEN}  ✓{Colors.NC} Repository cloned successfully\n")
        except RuntimeError as e:
            print(f"{Colors.RED}  ✗{Colors.NC} Failed to clone repository")
            raise

    def inject_factory_components(self):
        """Copy factory components to target repository"""
        print(f"{Colors.YELLOW}➤{Colors.NC} Injecting factory components...")

        for component in self.FACTORY_COMPONENTS:
            source = self.factory_root / component
            target = self.target_dir / component

            if not source.exists():
                print(f"{Colors.YELLOW}  ⚠{Colors.NC} Skipping {component} (not found in factory)")
                continue

            # Handle directories
            if source.is_dir():
                # Remove target directory if it exists (factory is source of truth)
                if target.exists():
                    print(f"{Colors.CYAN}    Replacing existing {component}{Colors.NC}")
                    shutil.rmtree(target)

                # Copy directory tree
                shutil.copytree(source, target)
                print(f"{Colors.GREEN}  ✓{Colors.NC} Installed {component}/")

            # Handle files
            else:
                # Create parent directories if needed
                target.parent.mkdir(parents=True, exist_ok=True)

                # Copy file (overwrite if exists)
                if target.exists():
                    print(f"{Colors.CYAN}    Replacing existing {component}{Colors.NC}")

                shutil.copy2(source, target)
                print(f"{Colors.GREEN}  ✓{Colors.NC} Installed {component}")

        print()

    def commit_and_push(self):
        """Commit changes and push to remote"""
        print(f"{Colors.YELLOW}➤{Colors.NC} Committing factory upgrade...")

        # Configure git user (required for commit)
        self._run_command([
            'git', 'config', 'user.email', 'factory@billyrinksglobal.com'
        ], cwd=self.target_dir)

        self._run_command([
            'git', 'config', 'user.name', 'Factory Installer'
        ], cwd=self.target_dir)

        # Stage all factory components
        self._run_command(['git', 'add', '-A'], cwd=self.target_dir)

        # Check if there are changes to commit
        returncode, stdout, _ = self._run_command(
            ['git', 'status', '--porcelain'],
            cwd=self.target_dir,
            check=False
        )

        if not stdout.strip():
            print(f"{Colors.YELLOW}  ⚠{Colors.NC} No changes detected - factory may already be installed")
            return

        # Commit changes
        commit_message = "feat: upgrade system to Autonomous Factory Standard"
        self._run_command([
            'git', 'commit', '-m', commit_message
        ], cwd=self.target_dir)

        print(f"{Colors.GREEN}  ✓{Colors.NC} Changes committed\n")

        # Push to remote
        print(f"{Colors.YELLOW}➤{Colors.NC} Pushing to remote repository...")

        try:
            self._run_command([
                'git', 'push', 'origin', 'main'
            ], cwd=self.target_dir)
            print(f"{Colors.GREEN}  ✓{Colors.NC} Successfully pushed to remote\n")
        except RuntimeError:
            # Try 'master' branch if 'main' fails
            print(f"{Colors.YELLOW}  ⚠{Colors.NC} 'main' branch not found, trying 'master'...")
            self._run_command([
                'git', 'push', 'origin', 'master'
            ], cwd=self.target_dir)
            print(f"{Colors.GREEN}  ✓{Colors.NC} Successfully pushed to remote\n")

    def validate_installation(self):
        """Validate that installation was successful"""
        print(f"{Colors.YELLOW}➤{Colors.NC} Validating installation...")

        # Check that key components exist
        validation_passed = True
        for component in ['.github/workflows', 'scripts', 'CLAUDE.md']:
            component_path = self.target_dir / component
            if not component_path.exists():
                print(f"{Colors.RED}  ✗{Colors.NC} Missing: {component}")
                validation_passed = False

        if validation_passed:
            print(f"{Colors.GREEN}  ✓{Colors.NC} All components validated\n")
        else:
            print(f"{Colors.RED}  ✗{Colors.NC} Validation failed\n")
            raise RuntimeError("Installation validation failed")

    def cleanup(self):
        """Clean up temporary directory"""
        if self.temp_dir and Path(self.temp_dir).exists():
            shutil.rmtree(self.temp_dir)
            print(f"{Colors.CYAN}  ℹ{Colors.NC} Cleaned up temporary files\n")

    def print_summary(self):
        """Print installation summary"""
        print(f"{Colors.BLUE}{'=' * 60}{Colors.NC}")
        print(f"{Colors.GREEN}✓ Factory Installation Complete!{Colors.NC}")
        print(f"{Colors.BLUE}{'=' * 60}{Colors.NC}\n")

        print("Installed components:")
        print("  • Workflows (.github/workflows/)")
        print("  • Scripts (scripts/)")
        print("  • Configuration (config/)")
        print("  • Constitution (CLAUDE.md)")
        print("  • Dependencies (requirements.txt)")
        print()

        print("The target repository has been upgraded to:")
        print("  🤖 Autonomous Factory Standard")
        print()

        print("Next steps:")
        print(f"  1. Visit: {self.target_repo_url}")
        print("  2. Review the changes in the latest commit")
        print("  3. Configure required secrets (ANTHROPIC_API_KEY, FACTORY_ADMIN_TOKEN)")
        print("  4. The factory will automatically begin assessment and improvement")
        print()

    def install(self):
        """Execute the complete installation process"""
        try:
            self.print_banner()
            self.clone_target_repo()
            self.inject_factory_components()
            self.commit_and_push()
            self.validate_installation()
            self.print_summary()
        except Exception as e:
            print(f"\n{Colors.RED}Installation failed: {e}{Colors.NC}\n")
            raise
        finally:
            self.cleanup()


def main():
    """Main entry point"""
    if len(sys.argv) != 2:
        print(f"{Colors.RED}Usage: python scripts/install_remote.py <target_repo_url>{Colors.NC}")
        print(f"\nExample: python scripts/install_remote.py https://github.com/user/repo")
        sys.exit(1)

    target_repo_url = sys.argv[1]

    try:
        installer = FactoryInstaller(target_repo_url)
        installer.install()
        print(f"{Colors.GREEN}🎉 Installation successful!{Colors.NC}\n")
        sys.exit(0)
    except Exception as e:
        print(f"\n{Colors.RED}❌ Installation failed: {e}{Colors.NC}\n")
        sys.exit(1)


if __name__ == '__main__':
    main()
