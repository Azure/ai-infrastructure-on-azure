# Git Workflow for Docusaurus Website

## ✅ Files That SHOULD Be Committed

### Configuration Files
- `docusaurus.config.js` - Site configuration
- `sidebars.js` - Sidebar navigation
- `package.json` - Node dependencies
- `package-lock.json` - Locked dependency versions
- `.gitignore` - Git ignore rules

### Scripts
- `build.sh` - Build automation script
- `serve.sh` - Local server script
- `clean.sh` - Clean generated files
- `sync-readmes.sh` - README sync script
- `postprocess-mdx.sh` - MDX post-processing
- `fix-links.sh` - Link fixing script

### Source Files
- `src/` - React components and pages
- `static/` - Static assets (images, etc.)
- `README.md` - Documentation

## ❌ Files That Should NOT Be Committed

### Generated Content
- `docs/` - Generated from repository READMEs (run `sync-readmes.sh` to regenerate)
- `build/` - Docusaurus build output
- `.docusaurus/` - Docusaurus cache
- `node_modules/` - NPM dependencies

These are all listed in `.gitignore` and will be automatically excluded.

## Workflow

### Before Committing

1. **Clean generated files:**
   ```bash
   ./clean.sh
   ```

2. **Check git status:**
   ```bash
   git status
   ```

3. **Verify only source files are staged:**
   - Configuration files ✅
   - Scripts ✅
   - Source files (src/, static/) ✅
   - Generated docs/ ❌
   - Build output ❌

### After Cloning/Pulling

1. **Install dependencies:**
   ```bash
   npm install
   ```

2. **Generate docs and build:**
   ```bash
   ./build.sh
   ```

3. **Preview locally:**
   ```bash
   ./serve.sh
   ```

## Why This Approach?

The `docs/` directory is generated from README files throughout the repository. This keeps the source of truth in the repository READMEs while providing a clean documentation site. The build script regenerates these docs from the latest README content.
