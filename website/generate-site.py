#!/usr/bin/env python3
"""
Generate Docusaurus site structure from YAML configuration.

This script reads site-structure.yaml and generates:
1. sidebars.js - Docusaurus sidebar configuration
2. Markdown files in docs/ with proper frontmatter
"""

import os
import sys
import yaml
from pathlib import Path
from typing import Dict, List, Any


def load_config(config_file: str = "site-structure.yaml") -> Dict:
    """Load the YAML configuration file."""
    with open(config_file, 'r') as f:
        return yaml.safe_load(f)


def get_doc_path(section_path: List[str], item_id: str) -> str:
    """Generate the document path from section hierarchy."""
    if not section_path:
        return item_id
    return "/".join(section_path + [item_id])


def generate_sidebar_item(item: Dict, section_path: List[str] = None) -> Any:
    """Generate a sidebar item (page or category)."""
    section_path = section_path or []
    
    if item.get('type') == 'page':
        # Simple page reference
        return item['id']
    
    elif item.get('type') == 'category':
        # Category with nested items
        category = {
            'type': 'category',
            'label': item['label'],
            'items': []
        }
        
        new_path = section_path + [item['id']]
        for child in item.get('items', []):
            category['items'].append(
                generate_sidebar_item(child, new_path)
            )
        
        return category
    
    else:
        # Regular document
        return get_doc_path(section_path, item['id'])


def generate_sidebars_js(config: Dict, output_file: str = "sidebars.js"):
    """Generate the sidebars.js file from configuration."""
    
    sidebar_items = []
    
    for section in config['site']['sections']:
        if section.get('type') == 'page':
            sidebar_items.append(section['id'])
        elif section.get('type') == 'category':
            sidebar_items.append(generate_sidebar_item(section, []))
        else:
            # Top-level document
            sidebar_items.append(section['id'])
    
    # Generate JavaScript file
    js_content = """/**
 * Creating a sidebar enables you to:
 - create an ordered group of docs
 - render a sidebar for each doc of that group
 - provide next/previous navigation

 The sidebars can be generated from the filesystem, or explicitly defined here.

 Create as many sidebars as you want.
 
 This file is auto-generated from site-structure.yaml
 Do not edit directly - run ./generate-site.py instead
 */

// @ts-check

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  tutorialSidebar: """
    
    # Convert Python structure to JavaScript
    import json
    js_items = json.dumps(sidebar_items, indent=4)
    js_content += js_items.replace('true', 'true').replace('false', 'false')
    
    js_content += """,
};

module.exports = sidebars;
"""
    
    with open(output_file, 'w') as f:
        f.write(js_content)
    
    print(f"✅ Generated {output_file}")


def create_markdown_file(item: Dict, section_path: List[str], base_path: str = ".."):
    """Create a markdown file with frontmatter from a README."""
    
    if not item.get('source'):
        return  # No source file (e.g., intro.md)
    
    # Build output path
    doc_path = get_doc_path(section_path, item['id'])
    output_file = f"docs/{doc_path}.md"
    
    # Create directory if needed
    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    
    # Read source README
    source_file = f"{base_path}/{item['source']}"
    try:
        with open(source_file, 'r') as f:
            content = f.read()
    except FileNotFoundError:
        print(f"⚠️  Warning: Source file not found: {source_file}")
        return
    
    # Generate frontmatter
    frontmatter = "---\n"
    frontmatter += f"title: {item['title']}\n"
    frontmatter += f"sidebar_label: {item['sidebar_label']}\n"
    
    if item.get('tags'):
        tags_str = '[' + ', '.join(item['tags']) + ']'
        frontmatter += f"tags: {tags_str}\n"
    
    frontmatter += "---\n\n"
    
    # Write output file
    with open(output_file, 'w') as f:
        f.write(frontmatter)
        f.write(content)
    
    print(f"📄 Created {output_file}")


def process_items(items: List[Dict], section_path: List[str], base_path: str = ".."):
    """Recursively process items and create markdown files."""
    
    for item in items:
        if item.get('type') == 'category':
            # Process nested items
            new_path = section_path + [item['id']]
            process_items(item.get('items', []), new_path, base_path)
        else:
            # Create markdown file for this item
            if item.get('source'):
                create_markdown_file(item, section_path, base_path)


def generate_docs(config: Dict, base_path: str = ".."):
    """Generate all documentation markdown files."""
    
    # Clean docs directory (except intro.md and _category_.json files)
    docs_dir = Path("docs")
    if docs_dir.exists():
        for item in docs_dir.rglob("*"):
            if item.is_file() and item.name not in ["intro.md", "_category_.json"]:
                item.unlink()
        # Remove empty directories
        for item in sorted(docs_dir.rglob("*"), reverse=True):
            if item.is_dir() and not any(item.iterdir()):
                item.rmdir()
    
    print("🧹 Cleaned docs directory (preserved intro.md)")
    
    # Process all sections
    for section in config['site']['sections']:
        if section.get('type') == 'category':
            process_items(section.get('items', []), [section['id']], base_path)
        elif section.get('source'):
            # Top-level document
            create_markdown_file(section, [], base_path)
    
    print("✅ Generated all documentation files")


def main():
    """Main entry point."""
    print("🚀 Generating Docusaurus site from site-structure.yaml")
    print("=" * 60)
    
    # Load configuration
    try:
        config = load_config()
    except FileNotFoundError:
        print("❌ Error: site-structure.yaml not found")
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"❌ Error parsing YAML: {e}")
        sys.exit(1)
    
    print("📋 Loaded configuration")
    
    # Generate sidebars.js
    generate_sidebars_js(config)
    
    # Generate documentation files
    generate_docs(config)
    
    print("=" * 60)
    print("✅ Site generation complete!")
    print()
    print("Next steps:")
    print("  1. Run ./postprocess-mdx.sh to fix MDX syntax")
    print("  2. Run ./fix-links.sh to fix relative links")
    print("  3. Run npm run build to build the site")
    print()
    print("Or simply run: ./build.sh")


if __name__ == "__main__":
    main()
