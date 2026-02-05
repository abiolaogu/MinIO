#!/usr/bin/env python3
"""
Autonomous Growth Engine
Generates 4 new product repositories per day based on System Architect Configuration.
"""

import os
import sys
import json
import yaml
import subprocess
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional

try:
    from anthropic import Anthropic
except ImportError:
    print("❌ Error: anthropic library not installed")
    print("Please run: pip install anthropic")
    sys.exit(1)


class AutonomousGrowthEngine:
    """Orchestrates autonomous product creation."""

    def __init__(self):
        """Initialize the growth engine."""
        self.base_path = Path(__file__).parent.parent
        self.anthropic_key = os.getenv('ANTHROPIC_API_KEY')
        self.github_token = os.getenv('FACTORY_ADMIN_TOKEN')
        self.github_owner = os.getenv('GITHUB_REPOSITORY_OWNER', 'billyronks')

        if not self.anthropic_key:
            raise ValueError("ANTHROPIC_API_KEY environment variable not set")
        if not self.github_token:
            raise ValueError("FACTORY_ADMIN_TOKEN environment variable not set")

        self.client = Anthropic(api_key=self.anthropic_key)
        self.created_repos = []

    def read_research_insights(self) -> Dict:
        """Read latest research insights from daily briefing."""
        print("📚 Reading research insights...")
        
        # Note: Even if unused by the new System Architect prompt, we keep this 
        # for logging and potential future context injection.
        briefing_path = self.base_path / 'docs' / 'product' / 'research' / 'daily_briefing.md'
        insights_dir = self.base_path / 'research' / 'insights'

        insights = {
            'daily_briefing': '',
            'additional_insights': []
        }

        if briefing_path.exists():
            with open(briefing_path, 'r') as f:
                insights['daily_briefing'] = f.read()
            print(f"   ✓ Read daily briefing ({len(insights['daily_briefing'])} chars)")
        else:
            print("   ⚠️  No daily briefing found")

        return insights

    def read_repo_index(self) -> Dict:
        """Read the repository index for reusable components."""
        print("📦 Reading repository index...")

        manifest_path = self.base_path / '.repo-index' / 'manifest.yaml'
        components_path = self.base_path / '.repo-index' / 'components.yaml'

        index = {
            'manifest': {},
            'components': []
        }

        if manifest_path.exists():
            with open(manifest_path, 'r') as f:
                index['manifest'] = yaml.safe_load(f) or {}
            print(f"   ✓ Read manifest with {len(index['manifest'].get('components', []))} components")

        return index

    def generate_product_idea(self, insights: Dict, repo_index: Dict, attempt: int) -> Optional[Dict]:
        """Use Claude to generate a product idea based on System Architect Configuration."""
        print(f"\n💡 Generating product idea #{attempt} via System Architect...")

        # 1. READ THE BRAIN (System Configuration)
        config_path = self.base_path / 'config' / 'system_architect.txt'
        
        if not config_path.exists():
            print(f"❌ Error: Configuration file not found at {config_path}")
            print("Please create config/system_architect.txt first.")
            return None

        with open(config_path, 'r') as f:
            system_prompt = f.read()

        # 2. ADD TIME CONTEXT (To ensure freshness)
        current_time = datetime.now().isoformat()

        try:
            # 3. CALL CLAUDE
            # We send the system_prompt as the "system" parameter.
            # We append the research insights to the user message so the architect 
            # has context, even if the system prompt controls the behavior.
            
            user_context = f"Generate a new product. Current Time: {current_time}.\n\n"
            user_context += f"Available Market Context: {insights.get('daily_briefing', 'None')[:500]}...\n"
            user_context += "Go."

            message = self.client.messages.create(
                model="claude-3-5-sonnet-20241022",
                max_tokens=4000,
                system=system_prompt,  # <--- HARDWIRED BRAIN
                messages=[
                    {"role": "user", "content": user_context}
                ]
            )

            response_text = message.content[0].text.strip()

            # Extract JSON from response
            if '```json' in response_text:
                json_start = response_text.find('```json') + 7
                json_end = response_text.find('```', json_start)
                response_text = response_text[json_start:json_end].strip()
            elif '```' in response_text:
                json_start = response_text.find('```') + 3
                json_end = response_text.find('```', json_start)
                response_text = response_text[json_start:json_end].strip()

            # The System Architect returns a structure with "repo_name" and "files"
            # We map this to the format expected by the rest of the script
            architect_output = json.loads(response_text)
            
            # Normalize output to match expected internal dictionary
            product_idea = {
                "name": architect_output.get("repo_name", "Unnamed Product"),
                "description": architect_output.get("description", ""),
                "target_market": "defined_by_architect",
                "source": "autonomous_system_architect",
                "confidence_score": 95, # High confidence due to strict system prompt
                "features": [],
                "tech_stack": {"backend": "defined_by_architect"},
                # Store the full file structure generated by the architect for the next step
                "generated_files": architect_output.get("files", []) 
            }

            print(f"   ✓ Generated: {product_idea['name']}")
            print(f"   ✓ Strategy: System Architect (Holy Trinity Mode)")

            return product_idea

        except Exception as e:
            print(f"   ✗ Error generating idea: {e}")
            return None

    def generate_scaffolding(self, product_idea: Dict) -> Dict:
        """
        Generate scaffolding. 
        If the System Architect already provided files, use them.
        Otherwise, fall back to generation.
        """
        
        # Check if System Architect provided the files directly (Optimization)
        if 'generated_files' in product_idea and product_idea['generated_files']:
            print(f"\n📝 Using Architect-defined scaffolding for {product_idea['name']}...")
            files = product_idea['generated_files']
            
            docs = {
                'readme': next((f['content'] for f in files if f['path'] == 'README.md'), "# Readme"),
                'prd': next((f['content'] for f in files if 'PRD' in f['path'] or 'domain' in f['path']), "# Logic"),
                'architecture': next((f['content'] for f in files if 'ARCHITECTURE' in f['path']), "# Architecture"),
                'all_files': files # Pass all files through
            }
            return docs

        # Fallback to legacy generation if architect didn't output file list
        print(f"\n📝 Generating scaffolding for {product_idea['name']} (Legacy Path)...")
        prompt = f"""Generate comprehensive documentation for: {json.dumps(product_idea, indent=2)}"""
        
        # ... (Legacy generation logic could remain here, but for brevity, we rely on the Architect)
        return {'readme': '# Error', 'prd': 'Error', 'architecture': 'Error'}

    def create_repository(self, product_idea: Dict, docs: Dict) -> Optional[str]:
        """Create a new GitHub repository using gh CLI."""
        print(f"\n🏗️  Creating repository for {product_idea['name']}...")

        # Generate repo name (lowercase, hyphenated)
        repo_name = product_idea['name'].lower().replace(' ', '-').replace('_', '-')
        full_repo_name = f"{self.github_owner}/{repo_name}"

        try:
            # Check if repo already exists
            check_cmd = ['gh', 'repo', 'view', full_repo_name]
            result = subprocess.run(check_cmd, capture_output=True, text=True, env={
                **os.environ,
                'GH_TOKEN': self.github_token
            })

            if result.returncode == 0:
                print(f"   ⚠️  Repository {full_repo_name} already exists, skipping")
                return None

            # Create repository from factory-template
            create_cmd = [
                'gh', 'repo', 'create', full_repo_name,
                '--template', 'abiolaogu/factory-template',
                '--private',
                '--clone'
            ]

            result = subprocess.run(create_cmd, capture_output=True, text=True, cwd=self.base_path, env={
                **os.environ,
                'GH_TOKEN': self.github_token
            })

            if result.returncode != 0:
                print(f"   ✗ Failed to create repository: {result.stderr}")
                return None

            print(f"   ✓ Created repository: {full_repo_name}")

            # Clone and add documentation/files
            repo_dir = self.base_path / repo_name

            if repo_dir.exists():
                # Write files provided by System Architect
                if 'all_files' in docs:
                    for file_obj in docs['all_files']:
                        file_path = repo_dir / file_obj['path']
                        # Ensure directory exists
                        file_path.parent.mkdir(parents=True, exist_ok=True)
                        file_path.write_text(file_obj['content'])
                        print(f"   ✓ Wrote {file_obj['path']}")
                else:
                    # Fallback for standard docs
                    (repo_dir / 'README.md').write_text(docs['readme'])
                    (repo_dir / 'docs' / 'PRD.md').write_text(docs['prd'])
                    (repo_dir / 'docs' / 'ARCHITECTURE.md').write_text(docs['architecture'])

                # Commit and push
                subprocess.run(['git', 'add', '.'], cwd=repo_dir, check=True)
                subprocess.run([
                    'git', 'commit', '-m',
                    f"feat: initialize {product_idea['name']} via System Architect\n\nCompliant with Factory Constitution v2.0"
                ], cwd=repo_dir, check=True)
                subprocess.run(['git', 'push'], cwd=repo_dir, check=True, env={
                    **os.environ,
                    'GH_TOKEN': self.github_token
                })

                print(f"   ✓ Pushed initial scaffolding")

            return f"https://github.com/{full_repo_name}"

        except Exception as e:
            print(f"   ✗ Error creating repository: {e}")
            return None

    def register_repository(self, product_idea: Dict, repo_url: str):
        """Add the new repository to the manifest."""
        print(f"\n📋 Registering repository in manifest...")

        manifest_path = self.base_path / '.repo-index' / 'manifest.yaml'

        try:
            # Read existing manifest
            if manifest_path.exists():
                with open(manifest_path, 'r') as f:
                    manifest = yaml.safe_load(f) or {}
            else:
                manifest = {'components': []}

            # Add new repository
            manifest['components'].append({
                'name': product_idea['name'],
                'url': repo_url,
                'description': product_idea['description'],
                'created': datetime.now().isoformat(),
                'reusable_components': product_idea.get('reusable_components', []),
                'tech_stack': product_idea.get('tech_stack', {})
            })

            # Write updated manifest
            manifest_path.parent.mkdir(parents=True, exist_ok=True)
            with open(manifest_path, 'w') as f:
                yaml.dump(manifest, f, default_flow_style=False)

            print(f"   ✓ Registered in manifest")

        except Exception as e:
            print(f"   ✗ Error registering repository: {e}")

    def create_product(self, insights: Dict, repo_index: Dict, attempt: int) -> Optional[Dict]:
        """Complete product creation flow."""
        print(f"\n{'=' * 60}")
        print(f"PRODUCT CREATION #{attempt}")
        print('=' * 60)

        # Generate idea via System Architect
        product_idea = self.generate_product_idea(insights, repo_index, attempt)
        if not product_idea:
            return None

        # Generate (or extract) scaffolding
        docs = self.generate_scaffolding(product_idea)

        # Create repository
        repo_url = self.create_repository(product_idea, docs)
        if not repo_url:
            return None

        # Register in manifest
        self.register_repository(product_idea, repo_url)

        result = {
            'product': product_idea,
            'url': repo_url,
            'timestamp': datetime.now().isoformat()
        }

        self.created_repos.append(result)

        print(f"\n✅ Product created successfully!")
        print(f"   URL: {repo_url}")

        return result

    def run_creator_loop(self, target_count: int = 4) -> List[Dict]:
        """Run the creator engine to generate new repositories."""
        print("\n" + "=" * 60)
        print("🚀 CREATOR ENGINE - STARTING")
        print("=" * 60)
        print(f"Target: {target_count} new repositories")

        # Read inputs
        insights = self.read_research_insights()
        repo_index = self.read_repo_index()

        # Create products
        created = []
        attempts = 0
        max_attempts = target_count * 3  # Allow up to 3 attempts per target

        while len(created) < target_count and attempts < max_attempts:
            attempts += 1
            result = self.create_product(insights, repo_index, attempts)
            if result:
                created.append(result)

        print("\n" + "=" * 60)
        print(f"✅ CREATOR ENGINE - COMPLETE")
        print(f"   Created: {len(created)}/{target_count} repositories")
        print("=" * 60)

        return created


def main():
    """Main entry point."""
    print("🏭 Autonomous Growth Engine (System Architect Mode)")
    print("=" * 60)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    try:
        engine = AutonomousGrowthEngine()

        # Run creator engine (4 repos)
        created_repos = engine.run_creator_loop(target_count=4)

        # Print summary
        print("\n" + "=" * 60)
        print("📊 SUMMARY")
        print("=" * 60)
        print(f"Repositories Created: {len(created_repos)}")

        for i, repo in enumerate(created_repos, 1):
            print(f"\n{i}. {repo['product']['name']}")
            print(f"   URL: {repo['url']}")
            print(f"   Source: {repo['product']['source']}")

        # Update growth dashboard
        dashboard_path = Path(__file__).parent.parent / 'docs' / 'GROWTH_DASHBOARD.md'
        update_dashboard(dashboard_path, created_repos, [])

        return 0

    except Exception as e:
        print(f"\n❌ Fatal error: {e}")
        import traceback
        traceback.print_exc()
        return 1


def update_dashboard(dashboard_path: Path, created_repos: List[Dict], refactor_prs: List[Dict]):
    """Update the growth dashboard with today's output."""
    print(f"\n📊 Updating growth dashboard at {dashboard_path}...")

    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    date_str = datetime.now().strftime('%Y-%m-%d')

    # Generate new entry
    entry = f"\n\n---\n\n## Growth Report: {date_str}\n"
    entry += f"**Generated:** {timestamp}\n\n"

    # Created repositories
    entry += "### Today's Output (Creator Engine)\n\n"
    if created_repos:
        for i, repo in enumerate(created_repos, 1):
            entry += f"{i}. **{repo['product']['name']}** - {repo['product']['description']}\n"
            entry += f"   - URL: [{repo['url']}]({repo['url']})\n"
            entry += f"   - Source: {repo['product']['source']}\n"
            entry += f"   - Confidence: {repo['product']['confidence_score']}/100\n"
            tech_items = [f"{k}: {v}" for k, v in repo['product'].get('tech_stack', {}).items()]
            entry += f"   - Tech Stack: {', '.join(tech_items)}\n\n"
    else:
        entry += "*No repositories created today*\n\n"

    # Refactor actions
    entry += "### Refactor Actions (Janitor Engine)\n\n"
    if refactor_prs:
        for i, pr in enumerate(refactor_prs, 1):
            entry += f"{i}. **{pr['title']}**\n"
            entry += f"   - PR: [{pr['url']}]({pr['url']})\n"
            entry += f"   - Repository: {pr['repo']}\n"
            entry += f"   - Type: {pr['type']}\n\n"
    else:
        entry += "*No refactoring actions today*\n\n"

    # Reuse metrics
    entry += "### Reuse Metrics\n\n"
    total_reused = sum(len(repo['product'].get('reusable_components', [])) for repo in created_repos)
    entry += f"- **Components Reused:** {total_reused}\n"
    entry += f"- **Net New Repositories:** {len(created_repos)}\n"

    try:
        # Read existing content
        if dashboard_path.exists():
            with open(dashboard_path, 'r') as f:
                existing_content = f.read()
        else:
            # Create initial content
            existing_content = """# Growth Dashboard

This dashboard tracks the autonomous generation of new repositories and daily refactoring actions.

## Overview

The Growth Engine operates in two modes:

1. **Creator Engine** (4 AM daily): Generates 4 new product repositories based on research insights
2. **Janitor Engine** (6 AM daily): Performs daily refactoring on existing repositories

"""

        # Append new entry
        dashboard_path.parent.mkdir(parents=True, exist_ok=True)
        with open(dashboard_path, 'w') as f:
            f.write(existing_content + entry)

        print(f"   ✓ Dashboard updated")

    except Exception as e:
        print(f"   ✗ Error updating dashboard: {e}")


if __name__ == '__main__':
    sys.exit(main())
