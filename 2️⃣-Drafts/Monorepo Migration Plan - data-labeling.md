# Monorepo Migration Plan: data-labeling

> **Goal**: Migrate `data-labeling` project to a monorepo structure that includes `@karlorz/react-image-annotate` as a workspace package, improving dependency management, development workflow, and atomic changes.

## Overview

### Current State
```
data-labeling/           # Main repo
├── web/                 # React frontend
├── svc/                 # Python backend
└── package.json         # Minimal root config

react-image-annotate/    # SEPARATE repo (external)
└── ...                  # Linked via `bun link`
```

### Target State
```
data-labeling/
├── apps/
│   └── web/             # React frontend (moved from ./web)
├── packages/
│   └── react-image-annotate/  # Library (merged)
├── svc/                 # Python backend (unchanged)
├── package.json         # Workspace root config
├── bun.lock             # Single lockfile
└── makefile             # Updated paths
```

> **Note**: This aligns with modern monorepo conventions (e.g., apps for deployable units, packages for shared libs). It enables automatic HMR, shared deps, and easier CI.

---

## Potential Pitfalls

- **Dependency Conflicts**: Workspace packages may expose version mismatches; resolve via `bun install --force`.
- **Bun Workspace Issues**: Ensure Bun >=1.1.x; watch for known bugs in workspace resolution with Vite.
- **Git History**: `git subtree` preserves history but may require manual conflict resolution.
- **Build Times**: Initial monorepo builds may be slower; consider Turborepo for caching (optional).
- **Import Paths**: Search codebase for hardcoded paths (e.g., `../web`, `./web`) and update to relative or aliased.
- **Vite/Fabric.js Compatibility**: Test that Vite resolves workspace packages correctly with existing Semi Design and Fabric.js setup.

---

## Migration Steps

### Phase 0: Preparation

#### Step 0.1: Backup and Verify
> **Note**: Working from branch `feat/clone`. All git push operations are manual (user handles).

```bash
# Ensure you're on the correct branch
git checkout feat/clone
git status

# Commit all pending changes (if any)
git commit -am "chore: pre-monorepo state"

# Verify current setup works
make all
cd web && bun run dev  # Test frontend
# Ctrl+C to stop

# Update Bun to latest
bun upgrade
bun --version  # Should be >=1.1.x
```

#### Step 0.2: Dependency Audit
```bash
# Check for duplicate/conflicting deps
cd web
bun pm ls | grep react-image-annotate
bun why @karlorz/react-image-annotate

# Note current versions for rollback reference
cat package.json | grep version
```

**Timeline**: 30-60 minutes

---

### Phase 1: Prepare Directory Structure

#### Step 1.1: Create new directories
```bash
cd /Users/karlchow/Desktop/code/data-labeling
mkdir -p apps packages

# Commit early for safety
git add apps packages
git commit -m "chore: add monorepo directories"
```

#### Step 1.2: Move web app to apps/
> **Warning**: This is destructive; double-check paths before running.

```bash
# Move the web directory
mv web apps/web

# Search for hardcoded paths that need updating
grep -r '\./web' --include="*.ts" --include="*.js" --include="*.json" --include="makefile" .
grep -r '../web' --include="*.ts" --include="*.js" --include="*.json" .

# Update any found references (e.g., in makefile, docker configs)

# Commit
git add -A
git commit -m "refactor: move web to apps/web"
```

#### Step 1.3: Merge react-image-annotate into packages/
> **Preferred**: Use `git subtree` to preserve history and enable future sync.

```bash
# Option A: Git subtree (RECOMMENDED - preserves history)
git subtree add --prefix=packages/react-image-annotate \
  git@github.com:karlorz/react-image-annotate.git main --squash

# Option B: Simple copy (loses git history)
# cp -r /path/to/react-image-annotate packages/react-image-annotate
# rm -rf packages/react-image-annotate/.git
# git add packages/react-image-annotate
# git commit -m "feat: add react-image-annotate as workspace package"
```

> **Note**: With `git subtree`, you can push changes back:
> ```bash
> git subtree push --prefix=packages/react-image-annotate \
>   git@github.com:karlorz/react-image-annotate.git main
> ```

**Timeline**: 1-2 hours
**Test**: Navigate to `packages/react-image-annotate` and verify structure.

---

### Phase 2: Configure Workspace

#### Step 2.1: Update root package.json
Replace the current minimal `package.json` with:

```json
{
  "name": "data-labeling",
  "private": true,
  "workspaces": [
    "apps/*",
    "packages/*"
  ],
  "scripts": {
    "dev": "bun run --cwd apps/web dev",
    "dev:lib": "bun run --cwd packages/react-image-annotate dev",
    "build": "bun run build:lib && bun run build:web",
    "build:web": "bun run --cwd apps/web build",
    "build:lib": "bun run --cwd packages/react-image-annotate build",
    "lint": "bun run --cwd apps/web lint",
    "type-check": "bun run --cwd apps/web type-check",
    "test": "bun test"
  },
  "devDependencies": {
    "typescript": "^5.9.3"
  }
}
```

#### Step 2.2: Update apps/web/package.json
Change the dependency from npm version to workspace:

```json
{
  "name": "@data-labeling/web",
  "private": true,
  "version": "0.2.6",
  "dependencies": {
    "@karlorz/react-image-annotate": "workspace:*"
  }
}
```

**Key change**: `"^4.0.7"` → `"workspace:*"`

#### Step 2.3: Verify packages/react-image-annotate/package.json
Ensure it has the correct name and entry points:

```json
{
  "name": "@karlorz/react-image-annotate",
  "version": "4.0.7",
  "main": "dist/index.js",
  "module": "dist/index.esm.js",
  "types": "dist/index.d.ts",
  "exports": {
    ".": {
      "import": "./dist/index.esm.js",
      "require": "./dist/index.js",
      "types": "./dist/index.d.ts"
    }
  }
}
```

#### Step 2.4: Install and verify
```bash
# Remove old lockfiles and node_modules
rm -rf apps/web/node_modules apps/web/bun.lock
rm -rf packages/react-image-annotate/node_modules

# Install all workspace dependencies
bun install

# Verify workspace linking
bun pm ls | grep react-image-annotate
# Should show: @karlorz/react-image-annotate@workspace:packages/react-image-annotate

# Commit
git add -A
git commit -m "feat: configure bun workspaces"
```

**Timeline**: 1 hour
**Test**: `bun run type-check` and `bun run lint`

---

### Phase 3: Update Build Configuration

#### Step 3.1: Update makefile paths

**Changes needed:**

```makefile
# OLD
FRONTEND_DIR = ./web

# NEW
FRONTEND_DIR = ./apps/web
LIB_DIR = ./packages/react-image-annotate
```

**Full updated makefile targets:**

```makefile
FRONTEND_DIR = ./apps/web
LIB_DIR = ./packages/react-image-annotate
BACKEND_DIR = .
VERSION_FILE = ./VERSION

.PHONY: all install build-frontend build-lib build-all start-frontend start-backend dev-lib dev-all test

# Install all workspace dependencies
install:
	@echo "Installing all workspace dependencies..."
	@bun install

# Build library first, then frontend
build-all: build-lib build-frontend

build-lib:
	@echo "Building react-image-annotate library..."
	@cd $(LIB_DIR) && bun run build

build-frontend:
	@echo "Building frontend..."
	@cd $(FRONTEND_DIR) && bun install && bun run build

# Local development: build all + start backend
all: build-all start-backend

# Start frontend dev with HMR
start-frontend:
	@echo "Starting frontend dev server..."
	@cd $(FRONTEND_DIR) && bun run dev

# Watch mode for library development
dev-lib:
	@echo "Starting library in watch mode..."
	@cd $(LIB_DIR) && bun run dev

# Parallel development (lib watch + frontend dev)
dev-all:
	@echo "Starting parallel development..."
	@(cd $(LIB_DIR) && bun run dev) & \
	 (cd $(FRONTEND_DIR) && bun run dev)

# Run tests
test:
	@echo "Running tests..."
	@bun test
```

**Remove these targets** (no longer needed):
- `link-annotate`
- `unlink-annotate`

**Keep and modify these targets**:
- `update-annotate` → Update to sync workspace package version
- `check-annotate` → Check local package vs published npm version

#### Step 3.2: Update Vite config

In `apps/web/vite.config.ts`, ensure workspace packages are resolved:

```typescript
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      // Explicit alias for workspace package (ensures HMR works)
      '@karlorz/react-image-annotate': path.resolve(
        __dirname,
        '../../packages/react-image-annotate/src'
      )
    }
  },
  // Pre-bundle workspace packages for faster dev startup
  optimizeDeps: {
    include: ['@karlorz/react-image-annotate']
  },
  // Watch workspace packages for changes
  server: {
    watch: {
      ignored: ['!**/packages/**']
    }
  }
})
```

**Test HMR**: Run `bun run dev:lib & bun run dev` and modify a file in packages/react-image-annotate.

#### Step 3.3: Update TypeScript config

In `apps/web/tsconfig.json`, add path mapping and project references:

```json
{
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "@karlorz/react-image-annotate": [
        "../../packages/react-image-annotate/src"
      ],
      "@karlorz/react-image-annotate/*": [
        "../../packages/react-image-annotate/src/*"
      ]
    }
  },
  "references": [
    { "path": "../../packages/react-image-annotate" }
  ]
}
```

**Timeline**: 1-2 hours
**Test**: `make build-all && make test`

---

### Phase 4: Update CI/CD and Docker

#### Step 4.1: Update .dockerignore
```dockerignore
# Ignore all node_modules
**/node_modules

# Ignore git
.git
.gitignore

# But include built files
!packages/react-image-annotate/dist
!apps/web/dist
```

#### Step 4.2: Update Dockerfile (if applicable)
```dockerfile
# Stage 1: Build
FROM oven/bun:1 as builder

WORKDIR /app

# Copy workspace config first (for better caching)
COPY package.json bun.lock ./
COPY apps/web/package.json ./apps/web/
COPY packages/react-image-annotate/package.json ./packages/react-image-annotate/

# Install dependencies
RUN bun install --frozen-lockfile

# Copy source files
COPY apps/web ./apps/web
COPY packages/react-image-annotate ./packages/react-image-annotate

# Build library then frontend
RUN bun run build:lib
RUN bun run build:web

# Stage 2: Production
FROM nginx:alpine
COPY --from=builder /app/apps/web/dist /usr/share/nginx/html
```

#### Step 4.3: Update GitHub Actions (if applicable)
```yaml
name: CI

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: oven-sh/setup-bun@v1
        with:
          bun-version: latest

      - name: Install dependencies
        run: bun install --frozen-lockfile

      - name: Type check
        run: bun run type-check

      - name: Lint
        run: bun run lint

      - name: Build library
        run: bun run build:lib

      - name: Build frontend
        run: bun run build:web

      - name: Run tests
        run: bun test
```

#### Step 4.4: Test Docker Build
```bash
docker compose build
docker compose up -d
# Verify app runs correctly
docker compose logs -f
```

**Timeline**: 1 hour

---

### Phase 5: Update Documentation

#### Step 5.1: Update CLAUDE.local.md / AGENTS.md

**Project Structure section:**
```markdown
## Project Structure
```
data-labeling/
├── apps/
│   └── web/                    # React frontend
├── packages/
│   └── react-image-annotate/   # Annotation library (workspace)
├── svc/                        # Python backend
├── package.json                # Workspace root config
├── bun.lock                    # Single lockfile for all JS
└── makefile
```
```

**Development Commands section:**
```markdown
### Essential Commands
```bash
# Install all dependencies (workspaces auto-linked)
bun install

# Development
make all                  # Build all + start backend
make start-frontend       # Frontend dev server only
make dev-lib              # Library watch mode
make dev-all              # Parallel lib + frontend dev (HMR)

# Build
make build-all            # Build lib then frontend
make build-lib            # Build library only
make build-frontend       # Build frontend only

# No more bun link needed!
```
```

#### Step 5.2: Update README.md
Add monorepo structure explanation and development workflow.

#### Step 5.3: Update PROJECT.md
Search for `./web` references and update to `./apps/web`:
```bash
grep -n '\./web' PROJECT.md
# Update each occurrence
```

**Timeline**: 30 minutes

---

## Post-Migration Checklist

### Verification Steps
- [ ] `bun install` completes without errors
- [ ] `bun pm ls` shows workspace package linked correctly
- [ ] `make build-lib` builds the library without errors
- [ ] `make build-frontend` builds the frontend without errors
- [ ] `make start-frontend` starts dev server on port 5173
- [ ] Changes in `packages/react-image-annotate/` trigger HMR in frontend
- [ ] TypeScript resolves imports from workspace package (no red squiggles)
- [ ] `bun run type-check` passes
- [ ] `bun run lint` passes
- [ ] Docker build works: `docker compose build`
- [ ] Docker run works: `docker compose up -d`
- [ ] CI/CD pipeline passes (if applicable)
- [ ] Performance: Build time comparable to before (benchmark)

### Clean Up
- [ ] Delete old `bun.lock` in `apps/web/` directory (if exists)
- [ ] Remove `link-annotate` and `unlink-annotate` from makefile
- [ ] Update all scripts referencing `./web` to `./apps/web`
- [ ] Update `.github/workflows/*.yml` if applicable
- [ ] Archive the separate react-image-annotate repository (mark as archived on GitHub)

---

## Rollback Plan

If issues arise, revert using one of these methods:

### Method 1: Git Revert (if phased commits used)
```bash
# Find the pre-migration commit
git log --oneline

# Revert to that commit
git revert --no-commit HEAD~N..HEAD  # N = number of migration commits
git commit -m "revert: rollback monorepo migration"
```

### Method 2: Manual Rollback
1. Move `apps/web` back to `web/`:
   ```bash
   mv apps/web web
   rm -rf apps
   ```
2. Remove `packages/` directory:
   ```bash
   rm -rf packages
   ```
3. Restore original `package.json`:
   ```bash
   git checkout HEAD~N -- package.json  # or restore from backup
   ```
4. Restore original `bun.lock`:
   ```bash
   rm bun.lock
   cd web && bun install
   ```
5. Re-run `bun link` workflow for external library

### Method 3: If using git subtree
```bash
# Extract package back to separate repo if needed
git subtree split --prefix=packages/react-image-annotate -b lib-backup
```

---

## Timeline Estimate

| Phase | Duration | Cumulative |
|-------|----------|------------|
| Phase 0: Preparation | 30-60 min | 1 hour |
| Phase 1: Directory Structure | 1-2 hours | 3 hours |
| Phase 2: Workspace Config | 1 hour | 4 hours |
| Phase 3: Build Config | 1-2 hours | 6 hours |
| Phase 4: CI/CD & Docker | 1 hour | 7 hours |
| Phase 5: Documentation | 30 min | 7.5 hours |
| Testing & Verification | 30 min | 8 hours |

**Total: 6-8 hours** (working on `feat/clone` branch, push when ready)

---

## Benefits Summary

| Aspect | Before | After |
|--------|--------|-------|
| New developer setup | Clone 2 repos + bun link | Clone 1 repo + bun install |
| Atomic changes | 2 commits, 2 PRs | 1 commit, 1 PR |
| Dependency management | Manual sync | Automatic via workspace |
| CI/CD complexity | 2 pipelines | 1 pipeline |
| HMR for library | Requires manual link | Works automatically |
| Testing | Separate test runs | Unified `bun test` |
| Version sync | Manual coordination | Workspace handles it |

---

## Future Enhancements (Optional)

### Turborepo for Build Caching
If the monorepo grows, consider adding Turborepo:
```bash
bun add -D turbo
```

Create `turbo.json`:
```json
{
  "pipeline": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**"]
    },
    "dev": {
      "cache": false
    }
  }
}
```

### Additional Packages
Structure for adding more packages:
```
packages/
├── react-image-annotate/    # Annotation library
├── shared-types/            # Shared TypeScript types
└── ui-components/           # Shared UI components
```

---

## References

- [Bun Workspaces Documentation](https://bun.sh/docs/install/workspaces)
- [Bun Workspace Best Practices](https://bun.sh/guides/install/workspaces)
- [Git Subtree Guide](https://www.atlassian.com/git/tutorials/git-subtree)
- [Vite Monorepo Guide](https://vitejs.dev/guide/ssr#monorepos)
- [Turborepo (optional enhancement)](https://turbo.build/repo/docs)
