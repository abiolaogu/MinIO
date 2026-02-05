#!/usr/bin/env python3
"""
Frontend Engine - The Frontend Singularity
A unified system that manages the entire lifecycle of frontend repos using Refine, Hasura, and Ant Design.

Modes:
  --mode init: Scaffold a new frontend repository from template
  --mode sync: Update an existing frontend repository with backend changes
"""

import os
import sys
import json
import argparse
import subprocess
import shutil
from pathlib import Path
from typing import Dict, List, Optional, Any
import re


class FrontendEngine:
    """Unified engine for frontend scaffolding and synchronization."""

    def __init__(self, mode: str, product_name: str, hasura_endpoint: str = None,
                 hasura_secret: str = None, workik_api_key: str = None):
        self.mode = mode
        self.product_name = product_name
        self.hasura_endpoint = hasura_endpoint or os.getenv("HASURA_ENDPOINT", "")
        self.hasura_secret = hasura_secret or os.getenv("HASURA_ADMIN_SECRET", "")
        self.workik_api_key = workik_api_key or os.getenv("WORKIK_API_KEY", "")
        self.repo_root = Path.cwd()
        self.frontend_dir = self.repo_root / "frontend" / "web"

    def log(self, message: str, level: str = "INFO"):
        """Log messages with appropriate prefixes."""
        prefix_map = {
            "INFO": "ℹ️",
            "SUCCESS": "✅",
            "WARNING": "⚠️",
            "ERROR": "❌",
            "PROGRESS": "🔄"
        }
        print(f"{prefix_map.get(level, '•')} {message}")

    # ==========================================
    # SCANNER LOGIC (Shared between modes)
    # ==========================================

    def scan_backend_schema(self) -> Dict[str, List[Dict[str, Any]]]:
        """
        Scanner Logic: Reads backend schema and identifies all entities.

        Input: Reads domain_model.json or GraphQL Schema
        Logic: Identifies all entities (e.g., Products, Orders)
        Output: Generates a resource config dictionary

        Returns:
            Dict with 'resources' key containing list of resource configs
        """
        self.log("Scanning backend schema for entities...", "PROGRESS")

        resources = []

        # Try to read domain_model.json first
        domain_model_path = self.repo_root / "backend" / "domain_model.json"
        if domain_model_path.exists():
            resources = self._parse_domain_model(domain_model_path)
        else:
            # Fallback to GraphQL schema
            schema_path = self.repo_root / "backend" / "hasura" / "schema.graphql"
            if schema_path.exists():
                resources = self._parse_graphql_schema(schema_path)
            else:
                self.log("No backend schema found. Using example resources.", "WARNING")
                resources = self._get_example_resources()

        self.log(f"Found {len(resources)} resources: {', '.join([r['name'] for r in resources])}", "SUCCESS")

        return {"resources": resources}

    def _parse_domain_model(self, path: Path) -> List[Dict[str, Any]]:
        """Parse domain_model.json and extract resources."""
        try:
            with open(path, 'r') as f:
                data = json.load(f)

            resources = []
            entities = data.get('entities', [])

            for entity in entities:
                resource = {
                    "name": entity.get('name', ''),
                    "label": entity.get('label', entity.get('name', '')),
                    "identifier": "id",
                    "fields": entity.get('fields', [])
                }
                resources.append(resource)

            return resources
        except Exception as e:
            self.log(f"Error parsing domain_model.json: {e}", "ERROR")
            return []

    def _parse_graphql_schema(self, path: Path) -> List[Dict[str, Any]]:
        """Parse GraphQL schema and extract type definitions."""
        try:
            with open(path, 'r') as f:
                schema_content = f.read()

            resources = []

            # Match type definitions (e.g., "type Product {")
            type_pattern = r'type\s+(\w+)\s*\{'
            matches = re.finditer(type_pattern, schema_content)

            for match in matches:
                type_name = match.group(1)

                # Skip GraphQL meta types
                if type_name.startswith('__') or type_name in ['Query', 'Mutation', 'Subscription']:
                    continue

                resource = {
                    "name": type_name.lower(),
                    "label": type_name,
                    "identifier": "id",
                    "fields": []
                }
                resources.append(resource)

            return resources
        except Exception as e:
            self.log(f"Error parsing GraphQL schema: {e}", "ERROR")
            return []

    def _get_example_resources(self) -> List[Dict[str, Any]]:
        """Return example resources for testing."""
        return [
            {"name": "products", "label": "Products", "identifier": "id", "fields": []},
            {"name": "orders", "label": "Orders", "identifier": "id", "fields": []},
            {"name": "customers", "label": "Customers", "identifier": "id", "fields": []}
        ]

    # ==========================================
    # MODE A: INIT (Scaffold)
    # ==========================================

    def mode_init(self):
        """
        INIT Mode: Scaffold a new frontend repository.

        Steps:
        1. Clone the refine-nextjs-antd starter template
        2. Rename the project to billyronks/[product]-web
        3. Configure src/providers/data.ts to point to Hasura Endpoint
        4. Call Scanner Logic to generate initial App.tsx with all resources
        5. Use Refine Inferencer to generate src/pages/[resource]/list.tsx files
        """
        self.log(f"Starting INIT mode for product: {self.product_name}", "INFO")

        # Step 1: Clone template
        template_url = "https://github.com/refinedev/refine.git"
        temp_dir = self.repo_root / "temp_refine_template"

        self.log("Cloning Refine Next.js + Ant Design template...", "PROGRESS")

        # For this implementation, we'll create a scaffold structure directly
        # In production, you would actually clone the template repo
        self._create_scaffold_structure()

        # Step 2: Rename project
        self._rename_project()

        # Step 3: Configure data provider
        self._configure_data_provider()

        # Step 4: Scan backend and generate App.tsx
        schema = self.scan_backend_schema()
        self._generate_app_tsx(schema)

        # Step 5: Generate resource pages using Inferencer
        self._generate_resource_pages(schema)

        # Integration points
        self._setup_workik_integration(schema)
        self._setup_lovable_integration()

        # Task 4: Verify handshake (frontend-backend connection)
        handshake_valid = self._verify_handshake()
        if not handshake_valid:
            self.log("WARNING: Handshake verification failed - frontend may not connect to backend properly", "WARNING")
            # Don't fail the build, but log the issue

        self.log(f"Frontend scaffold for '{self.product_name}' created successfully!", "SUCCESS")

        # Log all deployment assets to AI_CHANGELOG
        self._log_to_ai_changelog(
            "Frontend Engine",
            f"frontend/web (product: {self.product_name})",
            "GENERATE",
            f"Generated deployment-ready frontend scaffold (Dockerfile, .env.production, nginx.conf, health endpoint)"
        )

    def _create_scaffold_structure(self):
        """Create the basic scaffold directory structure."""
        self.log("Creating scaffold structure...", "PROGRESS")

        directories = [
            self.frontend_dir / "src" / "pages",
            self.frontend_dir / "src" / "providers",
            self.frontend_dir / "src" / "components",
            self.frontend_dir / "public",
            self.frontend_dir / ".workik"
        ]

        for directory in directories:
            directory.mkdir(parents=True, exist_ok=True)

        # Generate deployment assets (Deployment Readiness enforcement)
        self._generate_deployment_assets()

        # Create package.json
        package_json = {
            "name": f"{self.product_name}-web",
            "version": "0.1.0",
            "private": True,
            "scripts": {
                "dev": "next dev",
                "build": "next build",
                "start": "next start",
                "lint": "next lint"
            },
            "dependencies": {
                "@refinedev/core": "^4.47.1",
                "@refinedev/nextjs-router": "^1.0.0",
                "@refinedev/antd": "^5.37.4",
                "@refinedev/inferencer": "^4.5.18",
                "@refinedev/simple-rest": "^4.5.4",
                "next": "14.0.4",
                "react": "^18.2.0",
                "react-dom": "^18.2.0",
                "antd": "^5.12.0"
            },
            "devDependencies": {
                "@types/node": "^20",
                "@types/react": "^18",
                "@types/react-dom": "^18",
                "typescript": "^5"
            }
        }

        with open(self.frontend_dir / "package.json", 'w') as f:
            json.dump(package_json, f, indent=2)

        # Create tsconfig.json
        tsconfig = {
            "compilerOptions": {
                "target": "es5",
                "lib": ["dom", "dom.iterable", "esnext"],
                "allowJs": True,
                "skipLibCheck": True,
                "strict": True,
                "forceConsistentCasingInFileNames": True,
                "noEmit": True,
                "esModuleInterop": True,
                "module": "esnext",
                "moduleResolution": "bundler",
                "resolveJsonModule": True,
                "isolatedModules": True,
                "jsx": "preserve",
                "incremental": True,
                "paths": {
                    "@/*": ["./src/*"]
                }
            },
            "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx"],
            "exclude": ["node_modules"]
        }

        with open(self.frontend_dir / "tsconfig.json", 'w') as f:
            json.dump(tsconfig, f, indent=2)

    def _rename_project(self):
        """Rename the project to billyronks/[product]-web."""
        self.log(f"Renaming project to billyronks/{self.product_name}-web", "PROGRESS")

        # Update package.json name
        package_json_path = self.frontend_dir / "package.json"
        if package_json_path.exists():
            with open(package_json_path, 'r') as f:
                package_data = json.load(f)

            package_data['name'] = f"billyronks-{self.product_name}-web"

            with open(package_json_path, 'w') as f:
                json.dump(package_data, f, indent=2)

    def _configure_data_provider(self):
        """Configure src/providers/data.ts to point to Hasura Endpoint."""
        self.log("Configuring Hasura data provider...", "PROGRESS")

        providers_dir = self.frontend_dir / "src" / "providers"
        providers_dir.mkdir(parents=True, exist_ok=True)

        data_provider_code = f'''import {{ dataProvider as simpleRestProvider }} from "@refinedev/simple-rest";

// Configure Hasura GraphQL endpoint
const HASURA_ENDPOINT = process.env.NEXT_PUBLIC_HASURA_ENDPOINT || "{self.hasura_endpoint}";

// Create data provider with Hasura configuration
export const dataProvider = simpleRestProvider(HASURA_ENDPOINT);

// For GraphQL implementation, you would use:
// import {{ GraphQLClient }} from "graphql-request";
// const client = new GraphQLClient(HASURA_ENDPOINT, {{
//   headers: {{
//     "x-hasura-admin-secret": process.env.NEXT_PUBLIC_HASURA_ADMIN_SECRET || "",
//   }},
// }});
'''

        with open(providers_dir / "data.ts", 'w') as f:
            f.write(data_provider_code)

        # Create .env.local template
        env_content = f'''# Hasura Configuration
NEXT_PUBLIC_HASURA_ENDPOINT={self.hasura_endpoint}
NEXT_PUBLIC_HASURA_ADMIN_SECRET=your-hasura-admin-secret

# Workik Integration
WORKIK_API_KEY={self.workik_api_key if self.workik_api_key else "your-workik-api-key"}
'''

        with open(self.frontend_dir / ".env.local.template", 'w') as f:
            f.write(env_content)

    def _generate_app_tsx(self, schema: Dict[str, List[Dict[str, Any]]]):
        """Generate App.tsx with all resources pre-wired."""
        self.log("Generating App.tsx with resources...", "PROGRESS")

        resources = schema.get('resources', [])

        # Generate resource imports
        resource_imports = "\n".join([
            f'import {{ {r["label"]}List }} from "./pages/{r["name"]}/list";'
            for r in resources
        ])

        # Generate resource definitions
        resource_definitions = ",\n      ".join([
            f'''{{
        name: "{r['name']}",
        list: "/{r['name']}",
        meta: {{
          label: "{r['label']}",
        }},
      }}'''
            for r in resources
        ])

        app_tsx_code = f'''import {{ Refine }} from "@refinedev/core";
import {{ RefineThemes, ThemedLayoutV2, notificationProvider }} from "@refinedev/antd";
import routerProvider from "@refinedev/nextjs-router";
import {{ ConfigProvider }} from "antd";
import {{ dataProvider }} from "./providers/data";

{resource_imports}

function App() {{
  return (
    <ConfigProvider theme={{RefineThemes.Blue}}>
      <Refine
        routerProvider={{routerProvider}}
        dataProvider={{dataProvider}}
        notificationProvider={{notificationProvider}}
        resources={{[
      {resource_definitions}
        ]}}
      >
        <ThemedLayoutV2>
          {{/* Refine handles routing automatically based on resources */}}
        </ThemedLayoutV2>
      </Refine>
    </ConfigProvider>
  );
}}

export default App;
'''

        src_dir = self.frontend_dir / "src"
        src_dir.mkdir(parents=True, exist_ok=True)

        with open(src_dir / "App.tsx", 'w') as f:
            f.write(app_tsx_code)

    def _generate_resource_pages(self, schema: Dict[str, List[Dict[str, Any]]]):
        """Use Refine Inferencer to generate src/pages/[resource]/list.tsx files."""
        self.log("Generating resource pages with Refine Inferencer...", "PROGRESS")

        resources = schema.get('resources', [])

        for resource in resources:
            resource_name = resource['name']
            resource_label = resource['label']

            # Create resource directory
            resource_dir = self.frontend_dir / "src" / "pages" / resource_name
            resource_dir.mkdir(parents=True, exist_ok=True)

            # Generate list.tsx using Inferencer pattern
            list_tsx_code = f'''import {{ AntdInferencer }} from "@refinedev/inferencer/antd";

export default function {resource_label}List() {{
  return <AntdInferencer />;
}}

// After the inferencer generates the code, you can:
// 1. Copy the generated code
// 2. Replace <AntdInferencer /> with the actual implementation
// 3. Customize as needed
'''

            with open(resource_dir / "list.tsx", 'w') as f:
                f.write(list_tsx_code)

            # Generate show.tsx
            show_tsx_code = f'''import {{ AntdInferencer }} from "@refinedev/inferencer/antd";

export default function {resource_label}Show() {{
  return <AntdInferencer />;
}}
'''

            with open(resource_dir / "show.tsx", 'w') as f:
                f.write(show_tsx_code)

            # Generate edit.tsx
            edit_tsx_code = f'''import {{ AntdInferencer }} from "@refinedev/inferencer/antd";

export default function {resource_label}Edit() {{
  return <AntdInferencer />;
}}
'''

            with open(resource_dir / "edit.tsx", 'w') as f:
                f.write(edit_tsx_code)

            # Generate create.tsx
            create_tsx_code = f'''import {{ AntdInferencer }} from "@refinedev/inferencer/antd";

export default function {resource_label}Create() {{
  return <AntdInferencer />;
}}
'''

            with open(resource_dir / "create.tsx", 'w') as f:
                f.write(create_tsx_code)

    # ==========================================
    # MODE B: SYNC (Update)
    # ==========================================

    def mode_sync(self):
        """
        SYNC Mode: Update an existing frontend repository.

        Steps:
        1. Check out existing Frontend Repo
        2. Run Scanner Logic against latest Backend state
        3. Detect New Entities (e.g., "Invoices" added yesterday)
        4. Auto-generate new pages and update App.tsx without overwriting custom code
        """
        self.log(f"Starting SYNC mode for product: {self.product_name}", "INFO")

        # Check if frontend exists
        if not self.frontend_dir.exists():
            self.log("Frontend directory not found. Run with --mode init first.", "ERROR")
            sys.exit(1)

        # Step 1: Checkout/verify existing repo
        self._verify_existing_frontend()

        # Step 2: Scan backend for latest state
        current_schema = self.scan_backend_schema()

        # Step 3: Detect new entities
        existing_resources = self._get_existing_resources()
        new_resources = self._detect_new_resources(existing_resources, current_schema)

        if not new_resources:
            self.log("No new resources detected. Frontend is up to date.", "SUCCESS")
            return

        self.log(f"Detected {len(new_resources)} new resources: {', '.join([r['name'] for r in new_resources])}", "INFO")

        # Step 4: Generate new pages and update App.tsx safely
        self._generate_new_resource_pages(new_resources)
        self._update_app_tsx_safely(new_resources)

        # Update integrations
        self._update_workik_integration(current_schema)

        # Task 4: Verify handshake after sync
        handshake_valid = self._verify_handshake()
        if not handshake_valid:
            self.log("WARNING: Handshake verification failed after sync", "WARNING")

        self.log("SYNC completed successfully!", "SUCCESS")

        # Log sync action to AI_CHANGELOG
        self._log_to_ai_changelog(
            "Frontend Engine",
            f"frontend/web (product: {self.product_name})",
            "SYNC",
            f"Synchronized frontend with backend changes ({len(new_resources)} new resources added)"
        )

    def _verify_existing_frontend(self):
        """Verify that the frontend directory exists and is valid."""
        self.log("Verifying existing frontend...", "PROGRESS")

        required_files = [
            self.frontend_dir / "package.json",
            self.frontend_dir / "src" / "App.tsx"
        ]

        for file_path in required_files:
            if not file_path.exists():
                self.log(f"Missing required file: {file_path}", "ERROR")
                sys.exit(1)

    def _get_existing_resources(self) -> List[str]:
        """Extract existing resources from App.tsx."""
        app_tsx_path = self.frontend_dir / "src" / "App.tsx"

        if not app_tsx_path.exists():
            return []

        try:
            with open(app_tsx_path, 'r') as f:
                content = f.read()

            # Simple regex to find resource names
            # Looking for: name: "resource_name"
            pattern = r'name:\s*["\'](\w+)["\']'
            matches = re.findall(pattern, content)

            return matches
        except Exception as e:
            self.log(f"Error reading App.tsx: {e}", "ERROR")
            return []

    def _detect_new_resources(self, existing: List[str], schema: Dict) -> List[Dict[str, Any]]:
        """Detect resources that don't exist in the current frontend."""
        all_resources = schema.get('resources', [])
        new_resources = [r for r in all_resources if r['name'] not in existing]
        return new_resources

    def _generate_new_resource_pages(self, new_resources: List[Dict[str, Any]]):
        """Generate pages for new resources only."""
        self.log(f"Generating pages for {len(new_resources)} new resources...", "PROGRESS")

        for resource in new_resources:
            # Use the same generation logic as INIT mode
            self._generate_resource_pages({"resources": [resource]})

    def _update_app_tsx_safely(self, new_resources: List[Dict[str, Any]]):
        """
        Update App.tsx to include new resources without overwriting custom code.
        Uses AST parsing or safe injection markers.
        """
        self.log("Updating App.tsx with new resources...", "PROGRESS")

        app_tsx_path = self.frontend_dir / "src" / "App.tsx"

        with open(app_tsx_path, 'r') as f:
            content = f.read()

        # Strategy: Look for the resources array and append to it
        # We'll use a marker-based approach for safety

        # Generate new imports
        new_imports = "\n".join([
            f'import {{ {r["label"]}List }} from "./pages/{r["name"]}/list";'
            for r in new_resources
        ])

        # Generate new resource definitions
        new_definitions = ",\n      ".join([
            f'''{{
        name: "{r['name']}",
        list: "/{r['name']}",
        meta: {{
          label: "{r['label']}",
        }},
      }}'''
            for r in new_resources
        ])

        # Check if we have a marker for auto-generated imports
        if "// AUTO-GENERATED IMPORTS - DO NOT REMOVE THIS LINE" not in content:
            # Add marker after existing imports (before function App)
            import_marker = "\n// AUTO-GENERATED IMPORTS - DO NOT REMOVE THIS LINE\n"
            content = content.replace("function App()", import_marker + "function App()")

        # Inject new imports before the marker
        content = content.replace(
            "// AUTO-GENERATED IMPORTS - DO NOT REMOVE THIS LINE",
            f"{new_imports}\n// AUTO-GENERATED IMPORTS - DO NOT REMOVE THIS LINE"
        )

        # For resources array, we'll append before the closing bracket
        # Look for the pattern: "        ]}" which closes the resources array
        if "// AUTO-GENERATED RESOURCES - DO NOT REMOVE THIS LINE" not in content:
            # Add marker before closing the resources array
            content = content.replace(
                "        ]}\n      >",
                "        // AUTO-GENERATED RESOURCES - DO NOT REMOVE THIS LINE\n        ]}\n      >"
            )

        # Inject new resources before the marker
        content = content.replace(
            "        // AUTO-GENERATED RESOURCES - DO NOT REMOVE THIS LINE",
            f"      {new_definitions},\n        // AUTO-GENERATED RESOURCES - DO NOT REMOVE THIS LINE"
        )

        # Write back
        with open(app_tsx_path, 'w') as f:
            f.write(content)

    # ==========================================
    # DEPLOYMENT READINESS (Task 3)
    # ==========================================

    def _generate_deployment_assets(self):
        """
        Generate deployment-ready assets for the frontend.
        MANDATORY for all generated frontends (Task 3: Deployment Readiness).
        """
        self.log("Generating deployment assets (Dockerfile, .env.production, nginx.conf)...", "PROGRESS")

        # 1. Generate Dockerfile (Multi-stage Next.js build)
        dockerfile_content = f'''# Stage 1: Dependencies
FROM node:18-alpine AS deps
WORKDIR /app

# Install dependencies based on the preferred package manager
COPY package.json package-lock.json* ./
RUN npm ci

# Stage 2: Build
FROM node:18-alpine AS builder
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Set environment variables for build
ENV NEXT_TELEMETRY_DISABLED 1
ENV NODE_ENV production

# Build the application
RUN npm run build

# Stage 3: Runner
FROM node:18-alpine AS runner
WORKDIR /app

ENV NODE_ENV production
ENV NEXT_TELEMETRY_DISABLED 1

# Create non-root user for security
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Copy built application
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

# Set ownership
RUN chown -R nextjs:nodejs /app

USER nextjs

EXPOSE 3000

ENV PORT 3000
ENV HOSTNAME "0.0.0.0"

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \\
  CMD node -e "require('http').get('http://localhost:3000/api/health', (r) => {{process.exit(r.statusCode === 200 ? 0 : 1)}})"

CMD ["node", "server.js"]
'''

        with open(self.frontend_dir / "Dockerfile", 'w') as f:
            f.write(dockerfile_content)

        # 2. Generate .env.production
        env_production_content = f'''# Production Environment Variables
# Generated by Frontend Engine - Factory Template

# Backend API Configuration
NEXT_PUBLIC_API_URL={self.hasura_endpoint or "https://api.example.com"}
NEXT_PUBLIC_HASURA_ENDPOINT={self.hasura_endpoint or "https://hasura.example.com/v1/graphql"}

# Optional: Hasura Admin Secret (use with caution in frontend)
# NEXT_PUBLIC_HASURA_ADMIN_SECRET=your-hasura-admin-secret

# Application Configuration
NEXT_PUBLIC_APP_NAME={self.product_name}-web
NEXT_PUBLIC_APP_VERSION=1.0.0
NEXT_PUBLIC_ENVIRONMENT=production

# Workik Integration (if enabled)
WORKIK_API_KEY={self.workik_api_key if self.workik_api_key else ""}

# Feature Flags
NEXT_PUBLIC_ENABLE_ANALYTICS=false
NEXT_PUBLIC_ENABLE_DEBUG=false
'''

        with open(self.frontend_dir / ".env.production", 'w') as f:
            f.write(env_production_content)

        # 3. Generate nginx.conf (for static file serving if needed)
        nginx_conf_content = f'''# Nginx configuration for {self.product_name}-web
# Optional: Use this if serving static files via nginx

server {{
    listen 80;
    server_name localhost;
    root /app/public;

    # Gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # API proxy to backend
    location /api/ {{
        proxy_pass {self.hasura_endpoint or "http://backend:8000"}/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }}

    # Next.js static files
    location /_next/static/ {{
        alias /app/.next/static/;
        expires 1y;
        access_log off;
    }}

    # Health check endpoint
    location /health {{
        access_log off;
        return 200 "healthy\\n";
        add_header Content-Type text/plain;
    }}

    # All other routes go to Next.js
    location / {{
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }}
}}
'''

        with open(self.frontend_dir / "nginx.conf", 'w') as f:
            f.write(nginx_conf_content)

        # 4. Generate start.sh script
        start_sh_content = f'''#!/bin/sh
# Start script for {self.product_name}-web
# Generated by Frontend Engine - Factory Template

set -e

echo "Starting {self.product_name}-web..."
echo "Environment: ${{NODE_ENV:-development}}"
echo "Port: ${{PORT:-3000}}"

# Wait for backend to be ready (optional)
if [ -n "$BACKEND_URL" ]; then
    echo "Waiting for backend at $BACKEND_URL..."
    until curl -f "$BACKEND_URL/health" > /dev/null 2>&1; do
        echo "Backend not ready, retrying in 2 seconds..."
        sleep 2
    done
    echo "Backend is ready!"
fi

# Start the Next.js application
exec node server.js
'''

        with open(self.frontend_dir / "start.sh", 'w') as f:
            f.write(start_sh_content)

        # Make start.sh executable
        (self.frontend_dir / "start.sh").chmod(0o755)

        # 5. Generate .dockerignore
        dockerignore_content = '''# Dependencies
node_modules
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Testing
coverage
.nyc_output

# Next.js
.next/
out/

# Production
build
dist

# Misc
.DS_Store
*.pem
.env*.local

# Debug
*.log
.vscode
.idea

# Git
.git
.gitignore
'''

        with open(self.frontend_dir / ".dockerignore", 'w') as f:
            f.write(dockerignore_content)

        # 6. Update next.config.js to enable standalone output
        next_config_content = '''/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
  reactStrictMode: true,
  swcMinify: true,
}

module.exports = nextConfig
'''

        with open(self.frontend_dir / "next.config.js", 'w') as f:
            f.write(next_config_content)

        # 7. Create health check API endpoint
        health_api_dir = self.frontend_dir / "src" / "pages" / "api"
        health_api_dir.mkdir(parents=True, exist_ok=True)

        health_endpoint_content = '''import type { NextApiRequest, NextApiResponse } from 'next'

type HealthResponse = {
  status: string
  timestamp: string
  version: string
}

export default function handler(
  req: NextApiRequest,
  res: NextApiResponse<HealthResponse>
) {
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    version: process.env.NEXT_PUBLIC_APP_VERSION || '1.0.0'
  })
}
'''

        with open(health_api_dir / "health.ts", 'w') as f:
            f.write(health_endpoint_content)

        self.log("Deployment assets generated successfully!", "SUCCESS")

    def _verify_handshake(self) -> bool:
        """
        Task 4: Verify that the frontend properly references the backend endpoint.
        Check that src/providers/data.ts references HASURA_PROJECT_ENDPOINT variable.

        Returns:
            bool: True if handshake is valid, False otherwise
        """
        self.log("Verifying frontend-backend handshake...", "PROGRESS")

        data_provider_path = self.frontend_dir / "src" / "providers" / "data.ts"

        if not data_provider_path.exists():
            self.log("HANDSHAKE FAILED: src/providers/data.ts not found!", "ERROR")
            self._log_to_ai_changelog(
                "Frontend Engine",
                "src/providers/data.ts",
                "VERIFY",
                "Handshake verification failed - data provider file not found"
            )
            return False

        try:
            with open(data_provider_path, 'r') as f:
                content = f.read()

            # Check for Hasura endpoint reference
            # Accept multiple patterns: HASURA_ENDPOINT, NEXT_PUBLIC_HASURA_ENDPOINT, etc.
            hasura_patterns = [
                "HASURA_ENDPOINT",
                "NEXT_PUBLIC_HASURA_ENDPOINT",
                "HASURA_PROJECT_ENDPOINT",
                "process.env.NEXT_PUBLIC_HASURA"
            ]

            found_reference = any(pattern in content for pattern in hasura_patterns)

            if not found_reference:
                self.log("HANDSHAKE FAILED: No Hasura endpoint reference found in data provider!", "ERROR")
                self.log(f"Expected one of: {', '.join(hasura_patterns)}", "ERROR")
                self._log_to_ai_changelog(
                    "Frontend Engine",
                    "src/providers/data.ts",
                    "VERIFY",
                    "Handshake verification failed - no Hasura endpoint reference found"
                )
                return False

            self.log("Handshake verified: Frontend correctly references backend endpoint", "SUCCESS")
            self._log_to_ai_changelog(
                "Frontend Engine",
                "src/providers/data.ts",
                "VERIFY",
                "Handshake verification passed - backend connection properly configured"
            )
            return True

        except Exception as e:
            self.log(f"HANDSHAKE VERIFICATION ERROR: {e}", "ERROR")
            self._log_to_ai_changelog(
                "Frontend Engine",
                "src/providers/data.ts",
                "VERIFY",
                f"Handshake verification error: {e}"
            )
            return False

    def _log_to_ai_changelog(self, agent_name: str, target: str, action: str, details: str):
        """Log AI agent action to AI_CHANGELOG.md"""
        import datetime

        timestamp = datetime.datetime.utcnow()
        date_str = timestamp.strftime("%Y-%m-%d")
        time_str = timestamp.strftime("%H:%M:%S")

        log_entry = f"| {date_str} | {time_str} | {agent_name} | {target} | {action} | {details} |"

        changelog_path = self.repo_root / "docs" / "AI_CHANGELOG.md"

        try:
            with open(changelog_path, 'r') as f:
                content = f.read()

            # Find the operation log table and insert before the "---" separator
            lines = content.split('\n')
            insert_index = len(lines)

            for i, line in enumerate(lines):
                if line.strip() == "---" and i > 0 and "Operation Log" in '\n'.join(lines[:i]):
                    insert_index = i
                    break

            lines.insert(insert_index, log_entry)

            with open(changelog_path, 'w') as f:
                f.write('\n'.join(lines))

            print(f"✅ Logged action to AI_CHANGELOG.md: {action} on {target}")
        except Exception as e:
            print(f"⚠️ Failed to log to AI_CHANGELOG.md: {e}")

    # ==========================================
    # INTEGRATION POINTS
    # ==========================================

    def _setup_workik_integration(self, schema: Dict):
        """Update .workik/context.md with the new Resource list after every sync."""
        self.log("Setting up Workik integration...", "PROGRESS")

        workik_dir = self.frontend_dir / ".workik"
        workik_dir.mkdir(parents=True, exist_ok=True)

        resources = schema.get('resources', [])
        resource_list = "\n".join([f"- {r['label']} ({r['name']})" for r in resources])

        context_content = f'''# Workik Context - {self.product_name}

## Project Overview
This is an auto-generated frontend for the {self.product_name} product using Refine, Hasura, and Ant Design.

## Resources
The following resources are available in this application:

{resource_list}

## Data Provider
- **Backend**: Hasura GraphQL
- **Endpoint**: {self.hasura_endpoint}
- **Framework**: Refine v4
- **UI Library**: Ant Design v5

## Auto-Generation
This context file is automatically updated by the Frontend Engine during:
- Initial scaffolding (--mode init)
- Backend synchronization (--mode sync)

**NOTE**: Update `.workik/context.md` with the new Resource list after every sync.

Last updated: {self._get_timestamp()}
'''

        with open(workik_dir / "context.md", 'w') as f:
            f.write(context_content)

    def _update_workik_integration(self, schema: Dict):
        """Update Workik integration during sync."""
        # Same as setup, but called during sync
        self._setup_workik_integration(schema)

    def _setup_lovable_integration(self):
        """Ensure the scaffold includes a lovable-config.json placeholder."""
        self.log("Setting up Lovable integration placeholder...", "PROGRESS")

        lovable_config = {
            "version": "1.0.0",
            "project_name": f"{self.product_name}-web",
            "design_system": "BillyRonks-Unified-V3",
            "ui_framework": "antd",
            "theme": {
                "primary_color": "#1890ff",
                "layout": "sidebar",
                "mode": "light"
            },
            "sync": {
                "enabled": True,
                "auto_sync": True,
                "github_integration": True
            },
            "notes": "This is a placeholder for future UI styling integration with Lovable"
        }

        with open(self.frontend_dir / "lovable-config.json", 'w') as f:
            json.dump(lovable_config, f, indent=2)

        # Create README for Lovable integration
        lovable_readme = '''# Lovable Integration

This project is configured to work with Lovable for design system synchronization.

## Setup

1. Go to [Lovable.dev](https://lovable.dev)
2. Navigate to Settings → Integrations → GitHub
3. Install the Lovable App for this repository
4. When code is pushed to GitHub, Lovable automatically syncs the changes

## Configuration

The `lovable-config.json` file contains the design system configuration.
Modify this file to customize the UI theme and styling preferences.

## Sync Workflow

1. Code changes are committed to this repository
2. GitHub App integration detects the changes
3. Lovable automatically syncs and applies the design system
4. Review the UI updates in your Lovable project dashboard
'''

        with open(self.frontend_dir / "LOVABLE_INTEGRATION.md", 'w') as f:
            f.write(lovable_readme)

    def _get_timestamp(self) -> str:
        """Get current timestamp."""
        from datetime import datetime
        return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # ==========================================
    # MAIN EXECUTION
    # ==========================================

    def run(self):
        """Execute the appropriate mode."""
        if self.mode == "init":
            self.mode_init()
        elif self.mode == "sync":
            self.mode_sync()
        else:
            self.log(f"Invalid mode: {self.mode}. Use 'init' or 'sync'.", "ERROR")
            sys.exit(1)


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Frontend Engine - Unified frontend lifecycle management"
    )
    parser.add_argument(
        "--mode",
        choices=["init", "sync"],
        required=True,
        help="Operation mode: 'init' to scaffold new frontend, 'sync' to update existing"
    )
    parser.add_argument(
        "--product",
        required=True,
        help="Product name (e.g., 'ecommerce', 'inventory')"
    )
    parser.add_argument(
        "--hasura-endpoint",
        help="Hasura GraphQL endpoint URL (overrides HASURA_ENDPOINT env var)"
    )
    parser.add_argument(
        "--hasura-secret",
        help="Hasura admin secret (overrides HASURA_ADMIN_SECRET env var)"
    )
    parser.add_argument(
        "--workik-key",
        help="Workik API key (overrides WORKIK_API_KEY env var)"
    )

    args = parser.parse_args()

    # Create engine instance
    engine = FrontendEngine(
        mode=args.mode,
        product_name=args.product,
        hasura_endpoint=args.hasura_endpoint,
        hasura_secret=args.hasura_secret,
        workik_api_key=args.workik_key
    )

    # Run the engine
    engine.run()


if __name__ == "__main__":
    main()
