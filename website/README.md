# Docusaurus Documentation Site

This directory contains the Docusaurus-based documentation website for the AI Infrastructure on Azure repository.

## Quick Start

### Build the Site

From this directory:

```bash
./build.sh
```

This script will:
1. Sync README files from the repository
2. Post-process MDX syntax
3. Fix relative links between pages
4. Install dependencies (if needed)
5. Build the static site

### Clean Generated Files

Before committing changes, clean generated files:

```bash
./clean.sh
```

This removes:
- `docs/` (generated from repository READMEs)
- `build/` (Docusaurus build output)
- `.docusaurus/` (Docusaurus cache)

These directories are in `.gitignore` and should NOT be committed.

### Preview the Site

After building, start a local server:

```bash
./serve.sh
```

The site will be available at http://localhost:3000/

## Structure

```
docusaurus/
├── build.sh                 # Main build script
├── serve.sh                 # Local server script
└── website/                 # Docusaurus site files
    ├── docs/                # Documentation content
    ├── src/                 # React components
    ├── static/              # Static assets
    ├── docusaurus.config.js # Site configuration
    ├── sidebars.js          # Sidebar navigation
    ├── package.json         # Node dependencies
    ├── sync-readmes.sh      # Sync README files from repo
    ├── postprocess-mdx.sh   # Fix MDX compatibility
    └── fix-links.sh         # Fix relative links
```

## Development Workflow

### Updating Content

The documentation content comes from README files throughout the repository. The site structure is defined in `site-structure.yaml`.

**To add or modify documentation:**

1. Edit `site-structure.yaml` to add/modify/remove pages
2. Run the build script to regenerate everything:
   ```bash
   ./build.sh
   ```

The build script automatically:
1. Generates `sidebars.js` from the YAML
2. Copies README files with proper frontmatter
3. Post-processes MDX syntax
4. Fixes relative links
5. Builds the site

### Site Structure Configuration

Edit `site-structure.yaml` to control:
- Sidebar navigation hierarchy
- Page titles and labels
- Source README file mappings
- Tags for each page

Example entry:
```yaml
- id: my-page
  title: My Page Title
  sidebar_label: Short Label
  tags: [tag1, tag2]
  source: path/to/README.md
```

### Manual Updates

If you need to manually work with the Docusaurus site:

```bash
cd website

# Regenerate from YAML
./generate-site.py

# Install dependencies
npm install

# Start development server (with hot reload)
npm start

# Build for production
npm run build

# Serve production build
npm run serve
```

### Syncing README Files

When README files are updated in the repository, simply run:

```bash
./build.sh
```

This maintains the source of truth in the repository READMEs while providing a clean documentation site.

## Configuration

### Site Configuration

Edit `website/docusaurus.config.js` to modify:
- Site title, tagline, URL
- Navbar links
- Footer content
- Theme settings

### Sidebar Navigation

Edit `website/sidebars.js` to modify:
- Document organization
- Category structure
- Navigation hierarchy

## Deployment

The built site (in `website/build/`) can be deployed to any static hosting service:

- GitHub Pages
- Azure Static Web Apps
- Netlify
- Vercel
- etc.

For deployment configuration, see the [Docusaurus deployment docs](https://docusaurus.io/docs/deployment).

## Troubleshooting

### Build Warnings

Some warnings about broken links or anchors may appear. These typically come from:
- References to files not included in the documentation
- Missing anchor tags in original README files

To suppress warnings, modify the `onBrokenLinks` and `onBrokenAnchors` settings in `docusaurus.config.js`.

### Node Version

This site requires Node.js 18 or higher. Check your version:

```bash
node --version
```

If you need to upgrade, see the Node.js documentation.

## Resources

- [Docusaurus Documentation](https://docusaurus.io/)
- [Markdown Features](https://docusaurus.io/docs/markdown-features)
- [Docusaurus Configuration](https://docusaurus.io/docs/api/docusaurus-config)
- [YAML Configuration Guide](./YAML_CONFIG.md) - How to update the site structure
- [Git Workflow](./GIT_WORKFLOW.md) - What to commit and what not to commit
