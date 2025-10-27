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

The documentation content comes from README files throughout the repository. When README files are updated:

1. Run the build script to sync changes:
   ```bash
   ./build.sh
   ```

2. Preview the changes:
   ```bash
   ./serve.sh
   ```

### Manual Updates

If you need to manually work with the Docusaurus site:

```bash
cd website

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

The `website/sync-readmes.sh` script copies README files from the repository into the `website/docs/` directory with Docusaurus frontmatter. This maintains the source of truth in the repository READMEs while providing a clean documentation site.

Mapping:
- `infrastructure_references/` → `docs/infrastructure/`
- `infrastructure_validations/` → `docs/validations/`
- `examples/` → `docs/examples/`
- `utilities/` → `docs/guidance/`
- `storage_references/` → `docs/guidance/`

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
   - [Slurm version](./infrastructure_validations/slurm/NCCL/README.md)
   - [AKS version](./infrastructure_validations/aks/NCCL/README.md)
2. Node Health Checks - Automated system validation and monitoring for compute nodes
   - [Slurm version](./infrastructure_validations/slurm/NHC/README.md)
   - [AKS version](./infrastructure_validations/aks/NHC/README.md)
3. Thermal Test - GPU thermal stress testing and monitoring
   - [Slurm version](./infrastructure_validations/slurm/thermal_test/README.md)
4. FIO Storage Performance Testing - I/O performance testing with Azure Blob Storage and blobfuse
   - [AKS version](./infrastructure_validations/aks/blobfuse/README.md)

## Utilities catalog

1. Node Labeler - Automatically labels nodes with host information and InfiniBand HCA GUIDs for network topology awareness
   - [AKS version](./utilities/aks/node_labeler/helm/README.md)
2. Torset Labeler - Discovers and labels nodes with torset (InfiniBand switching domain) information using SHARP topology discovery
   - [AKS version](./utilities/aks/torset_labeler/helm/README.md)

## Contributing

This project welcomes contributions and suggestions. Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit <https://cla.opensource.microsoft.com>.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft
trademarks or logos is subject to and must follow
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos is subject to those third-party's policies.

## Contributors

Please join us in contributing to the project

[![Contributors](https://contrib.rocks/image?repo=Azure/ai-on-azure)](https://github.com/Azure/ai-infrastructure-on-azure/graphs/contributors)
