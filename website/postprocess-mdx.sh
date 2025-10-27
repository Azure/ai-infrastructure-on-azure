#!/bin/bash

# Post-process markdown files to fix common MDX compatibility issues

echo "Post-processing markdown files for MDX compatibility..."

# Find all .md files in docs directory
find docs -name "*.md" -type f | while read file; do
  echo "Processing: $file"
  
  # Fix HTML URLs like <http://...> -> http://...
  sed -i 's|<http://\([^>]*\)>|http://\1|g' "$file"
  sed -i 's|<https://\([^>]*\)>|https://\1|g' "$file"
  
  # Escape curly braces that aren't part of JSX
  # This is tricky - we'll do simple cases
  # sed -i 's/{\([^}]*\)}/{\\{\1\\}}/g' "$file"
  
  #  Fix HTML comments to JSX comments
  # sed -i 's/<!--/{\/\*/g' "$file"
  # sed -i 's/-->/\*\/}/g' "$file"
done

echo "✅ Post-processing complete!"
