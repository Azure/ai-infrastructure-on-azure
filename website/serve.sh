#!/bin/bash

# Serve script for Docusaurus documentation site
# Serves the built site locally for preview

cd "$(dirname "$0")/website"

if [ ! -d "build" ]; then
    echo "❌ Build directory not found. Please run ./build.sh first."
    exit 1
fi

echo "🌐 Starting Docusaurus local server..."
echo "=========================================="
echo "The site will be available at: http://localhost:3000/"
echo "Press Ctrl+C to stop the server"
echo "=========================================="
echo ""

npm run serve
