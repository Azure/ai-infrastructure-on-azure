#!/bin/bash

# Clean script for Docusaurus website
# Removes all generated and build artifacts before committing

set -e

echo "🧹 Cleaning Docusaurus website directory..."
echo "=========================================="

cd "$(dirname "$0")"

# Remove generated docs (these are copied from repository READMEs)
if [ -d "docs" ]; then
    echo "📋 Removing generated docs (preserving intro.md)..."
    # Remove all docs except intro.md
    find docs -type f -name "*.md" ! -name "intro.md" -delete
    find docs -type d -empty -delete
    echo "✅ Generated docs removed"
fi

# Remove build artifacts
if [ -d "build" ]; then
    echo "🏗️  Removing build directory..."
    rm -rf build
    echo "✅ build/ removed"
fi

# Remove Docusaurus cache
if [ -d ".docusaurus" ]; then
    echo "💾 Removing .docusaurus cache..."
    rm -rf .docusaurus
    echo "✅ .docusaurus/ removed"
fi

# Remove node_modules (optional - uncomment if you want to remove it)
# if [ -d "node_modules" ]; then
#     echo "📦 Removing node_modules..."
#     rm -rf node_modules
#     echo "✅ node_modules/ removed"
# fi

echo ""
echo "=========================================="
echo "✅ Clean complete!"
echo ""
echo "The following should NOT be committed:"
echo "  - docs/ (generated from READMEs)"
echo "  - build/ (Docusaurus build output)"
echo "  - .docusaurus/ (Docusaurus cache)"
echo "  - node_modules/ (npm dependencies)"
echo ""
echo "These are all listed in .gitignore"
echo "=========================================="
