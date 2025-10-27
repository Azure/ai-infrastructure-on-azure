# Git Workflow for Docusaurus Website

## ✅ Files That SHOULD Be Committed

### Configuration Files
- `site-structure.yaml` - **Main site configuration** (sidebar, pages, README mappings)
- `docusaurus.config.js` - Site configuration
- `package.json` - Node dependencies
- `package-lock.json` - Locked dependency versions
- `.gitignore` - Git ignore rules

### Scripts
- `generate-site.py` - **Generates sidebars.js and docs/ from YAML**
- `build.sh` - Build automation script
- `serve.sh` - Local server script
- `clean.sh` - Clean generated files
- `postprocess-mdx.sh` - MDX post-processing
- `fix-links.sh` - Link fixing script
- ~~`sync-readmes.sh`~~ - (Replaced by generate-site.py)

### Source Files
- `src/` - React components and pages
- `static/` - Static assets (images, etc.)
- `README.md` - Documentation

## ❌ Files That Should NOT Be Committed

### Generated Content
- `docs/` - Generated from YAML + repository READMEs (run `./generate-site.py` to regenerate)
- `sidebars.js` - Generated from `site-structure.yaml` (run `./generate-site.py` to regenerate)
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

The `docs/` directory and `sidebars.js` are generated from:
1. **`site-structure.yaml`** - Defines the site structure, navigation, and README mappings
2. **README files** throughout the repository - The actual content

This keeps the source of truth in the repository READMEs and makes it easy to update the site structure by editing a single YAML file. The build script regenerates everything from the YAML configuration.
