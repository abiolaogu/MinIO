#!/usr/bin/env python3
"""
Repository Improver Agent
Updated: Now calculates and updates completion percentage dynamically.
"""

import os
import json
import anthropic
import requests
from pathlib import Path
from datetime import datetime

class RepoImprover:
    def __init__(self, github_token, anthropic_api_key, github_repo):
        self.github_token = github_token
        self.anthropic_api_key = anthropic_api_key
        self.github_repo = github_repo
        self.client = anthropic.Anthropic(api_key=anthropic_api_key)
        self.assessment_file = Path(".factory-assessment.json")

    def load_assessment(self):
        """Load the assessment from repo_assessor."""
        if not self.assessment_file.exists():
            return {
                "goals_achieved": "PARTIAL",
                "prd_exists": False,
                "missing_docs": [],
                "completion_percentage": 50,
                "next_steps": "IMPROVE"
            }
        return json.loads(self.assessment_file.read_text())

    def save_assessment(self, assessment):
        """Save the updated assessment back to disk."""
        self.assessment_file.write_text(json.dumps(assessment, indent=2))
        print(f"📈 Updated local assessment: {assessment['completion_percentage']}%")

    def scan_codebase(self):
        """Scan the codebase to identify potential gaps."""
        repo_root = Path.cwd()

        # Check for common architectural patterns
        has_tests = any(repo_root.glob("**/test_*.py")) or any(repo_root.glob("**/tests/"))
        has_ci = (repo_root / ".github" / "workflows").exists()
        has_docker = (repo_root / "Dockerfile").exists()
        has_docs = (repo_root / "docs").exists()
        has_config = any([
            (repo_root / "config").exists(),
            (repo_root / ".env.example").exists(),
            (repo_root / "settings.py").exists()
        ])

        return {
            "has_tests": has_tests,
            "has_ci": has_ci,
            "has_docker": has_docker,
            "has_docs": has_docs,
            "has_config": has_config
        }

    def detect_architectural_gaps(self):
        """Detect missing architectural components and generate actionable issues."""
        codebase_info = self.scan_codebase()
        gaps = []

        if not codebase_info["has_tests"]:
            gaps.append({
                "title": "Missing Test Suite",
                "issue_type": "Testing Infrastructure",
                "fix_strategy": "Set up a comprehensive test suite with unit tests and integration tests. Use pytest for Python projects, Jest for JavaScript, or appropriate testing frameworks for other languages.",
                "technical_strategy": "1. Create tests/ directory\n2. Add test framework dependencies\n3. Write sample test files\n4. Configure test runner in CI/CD"
            })

        if not codebase_info["has_ci"]:
            gaps.append({
                "title": "Missing CI/CD Pipeline",
                "issue_type": "DevOps Infrastructure",
                "fix_strategy": "Implement GitHub Actions workflows for automated testing, linting, and deployment.",
                "technical_strategy": "1. Create .github/workflows/ci.yml\n2. Add linting and testing jobs\n3. Configure automated deployment\n4. Add status badges to README"
            })

        if not codebase_info["has_docker"]:
            gaps.append({
                "title": "Missing Container Configuration",
                "issue_type": "Deployment Infrastructure",
                "fix_strategy": "Add Dockerfile and docker-compose.yml for consistent development and deployment environments.",
                "technical_strategy": "1. Create Dockerfile with multi-stage build\n2. Add docker-compose.yml for local development\n3. Document container usage in README\n4. Add .dockerignore file"
            })

        if not codebase_info["has_docs"]:
            gaps.append({
                "title": "Missing Documentation Structure",
                "issue_type": "Documentation",
                "fix_strategy": "Create comprehensive documentation including API docs, architecture diagrams, and contribution guidelines.",
                "technical_strategy": "1. Create docs/ directory\n2. Add ARCHITECTURE.md\n3. Add CONTRIBUTING.md\n4. Add API documentation\n5. Set up documentation generator"
            })

        return gaps

    def generate_prd(self):
        """Generate a PRD and return True if successful."""
        assessment = self.load_assessment()
        if assessment.get('prd_exists'):
            return False

        readme_path = Path("README.md")
        readme_content = readme_path.read_text(encoding='utf-8') if readme_path.exists() else ""

        prompt = f"Generate a comprehensive PRD based on: {readme_content}"
        try:
            response = self.client.messages.create(
                model="claude-3-5-sonnet-20241022",
                max_tokens=4000,
                messages=[{"role": "user", "content": prompt}]
            )
            prd_path = Path("docs/PRD.md")
            prd_path.parent.mkdir(exist_ok=True)
            prd_path.write_text(response.content[0].text)
            print(f"✅ Generated PRD at {prd_path}")
            return True
        except Exception as e:
            print(f"Error generating PRD: {e}")
            return False

    def create_github_issue(self, title, body, labels=None):
        """Create a GitHub issue with @claude auto-trigger."""
        if not self.github_token or not self.github_repo:
            print(f"⚠️ Cannot create issue: {title}")
            return

        url = f"https://api.github.com/repos/{self.github_repo}/issues"
        headers = {
            "Authorization": f"token {self.github_token}",
            "Accept": "application/vnd.github.v3+json"
        }

        # Add explicit @claude trigger at the end
        formatted_body = f"**Automated Analysis:**\n\n{body}\n\n---\n\n**Action Required:**\n@claude implement this fix based on the analysis above."

        # Ensure auto-fix label is included
        issue_labels = labels or []
        if "auto-fix" not in issue_labels:
            issue_labels.append("auto-fix")

        data = {"title": title, "body": formatted_body, "labels": issue_labels}

        try:
            response = requests.post(url, headers=headers, json=data)
            if response.status_code == 201:
                print(f"✅ Created issue: {response.json()['html_url']}")
            else:
                print(f"⚠️ Failed to create issue: {response.status_code}")
        except Exception as e:
            print(f"Error creating issue: {e}")

    def run(self):
        """Run the improvement process and update progress."""
        print("🔧 Starting repository improvement...")
        assessment = self.load_assessment()
        initial_percentage = assessment.get('completion_percentage', 50)
        work_done_bonus = 0

        # 1. Handle PRD Generation (Worth 15% progress)
        if self.generate_prd():
            work_done_bonus += 15
            assessment['prd_exists'] = True

        # 2. Handle Improvements/Gaps
        if assessment['next_steps'] == 'IMPROVE':
            print("📈 Mode: IMPROVEMENT")
            gaps = self.detect_architectural_gaps()
            for gap in gaps:
                work_done_bonus += 5 # Each gap identified/fixed is worth 5%
                issue_body = f"""## Issue Type
{gap['issue_type']}

## Fix Strategy
{gap['fix_strategy']}

## Technical Strategy
{gap['technical_strategy']}"""
                self.create_github_issue(
                    title=f"🔧 Architecture Gap: {gap['title']}",
                    body=issue_body,
                    labels=["architecture", "improvement"]
                )
        else:
            print("🚧 Mode: CONTINUE DEVELOPMENT")
            # Creating the roadmap issue itself is progress (worth 5%)
            work_done_bonus += 5
            
            issue_body = f"## Status: {initial_percentage}%\n1. Review PRD\n2. Start implementation"
            self.create_github_issue(
                title=f"🚧 Continue Development: {initial_percentage + work_done_bonus}% Complete",
                body=issue_body,
                labels=["development", "in-progress"]
            )

        # Update and Save
        new_percentage = min(initial_percentage + work_done_bonus, 100)
        assessment['completion_percentage'] = new_percentage
        self.save_assessment(assessment)
        
        print(f"\n✅ Improvement complete! Progress: {initial_percentage}% -> {new_percentage}%")

# ... [Main block remains the same] ...
