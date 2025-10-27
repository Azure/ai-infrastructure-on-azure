# YAML-Based Site Configuration

## Overview

The Docusaurus site is now configured using a single YAML file (`site-structure.yaml`) that defines:
- Site navigation structure
- Page hierarchy and organization
- Source README file mappings
- Page titles, labels, and tags

This makes it easy to update the site by editing one file instead of multiple JavaScript and bash scripts.

## Files

### `site-structure.yaml`
Main configuration file that defines the entire site structure.

**Structure:**
```yaml
site:
  sections:
    - id: page-id
      type: page|category
      label: Display Name
      title: Page Title
      sidebar_label: Sidebar Label
      tags: [tag1, tag2]
      source: path/to/README.md
      items: [...]  # For categories
```

### `generate-site.py`
Python script that reads `site-structure.yaml` and generates:
- `sidebars.js` - Docusaurus sidebar configuration
- `docs/*.md` - Markdown files with frontmatter

## Workflow

### Adding a New Page

1. Add entry to `site-structure.yaml`:
```yaml
- id: my-new-page
  title: My New Page
  sidebar_label: New Page
  tags: [topic1, topic2]
  source: path/to/new/README.md
```

2. Run the build script:
```bash
./build.sh
```

Done! The page will be added to the sidebar and generated with proper frontmatter.

### Reorganizing the Site

Simply rearrange items in `site-structure.yaml` and run `./build.sh`.

### Updating Content

Content comes from repository READMEs. When README files are updated, run:
```bash
./build.sh
```

## Migration from Old System

**Old approach:**
- Edit `sync-readmes.sh` with HEREDOC blocks
- Edit `sidebars.js` manually
- Edit `fix-links.sh` for new pages
- Keep all three in sync manually

**New approach:**
- Edit `site-structure.yaml` only
- Run `./build.sh`
- Everything is regenerated automatically

## Benefits

1. **Single source of truth** - All structure in one YAML file
2. **Easier to maintain** - No need to edit multiple files
3. **Less error-prone** - Automatic generation reduces manual errors
4. **Self-documenting** - YAML is easy to read and understand
5. **Version controlled** - Easy to see structure changes in git diffs

## What's Generated (Should NOT be committed)

- `docs/` - All markdown files
- `sidebars.js` - Sidebar navigation

These are in `.gitignore` and regenerated from YAML on build.

## What Should Be Committed

- `site-structure.yaml` - Site structure definition
- `generate-site.py` - Generator script
- `build.sh` - Build script (updated to use generator)
- `postprocess-mdx.sh` - MDX post-processing
- `fix-links.sh` - Link fixing
- `docusaurus.config.js` - Docusaurus config
- `src/` - React components
- `static/` - Static assets
