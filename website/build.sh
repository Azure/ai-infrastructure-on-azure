#!/bin/bash

# Main build script for Docusaurus documentation site
# This script syncs README files, processes them, and builds the site

set -e  # Exit on error

echo "🚀 Building Docusaurus Documentation Site"
echo "=========================================="

# Ensure we're in the website directory
cd "$(dirname "$0")"

echo ""
echo "📋 Step 1: Generating site structure from YAML..."
./generate-site.py
if [ $? -eq 0 ]; then
    echo "✅ Site generation complete"
else
    echo "❌ Site generation failed"
    exit 1
fi

echo ""
echo "🔧 Step 2: Post-processing MDX compatibility..."
./postprocess-mdx.sh
if [ $? -eq 0 ]; then
    echo "✅ MDX post-processing complete"
else
    echo "❌ MDX post-processing failed"
    exit 1
fi

echo ""
echo "🔗 Step 3: Fixing relative links..."
./fix-links.sh
if [ $? -eq 0 ]; then
    echo "✅ Link fixing complete"
else
    echo "❌ Link fixing failed"
    exit 1
fi

echo ""
echo "📦 Step 4: Installing dependencies (if needed)..."
if [ ! -d "node_modules" ]; then
    npm install
else
    echo "✅ Dependencies already installed"
fi

echo ""
echo "🏗️  Step 5: Building Docusaurus site..."
npm run build

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "✅ Build complete!"
    echo ""
    echo "To preview the site locally, run:"
    echo "  npm run serve"
    echo ""
    echo "Or use the serve script:"
    echo "  ./serve.sh"
    echo "=========================================="
else
    echo ""
    echo "❌ Build failed"
    exit 1
fi
