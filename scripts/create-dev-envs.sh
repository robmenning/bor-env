#!/bin/bash

# Script to create amalgamated development environment files
# This script concatenates .env, .env.development, and .env.development.local files
# into a single development.env file in each container's parent directory
# Note: Reads from ../bor-secrets and creates files in ../<containername>/ directories

set -e  # Exit on any error

# Hard-coded container names for simplicity (same as create-prod-envs.sh)
CONTAINERS=(
    "bor-db"
    "bor-api"
    "bor-app"
    "bor-airflow"
    "bor-files"
    "bor-message"
)

# Function to create amalgamated development env file
create_development_env() {
    local container_name="$1"
    local source_dir="../bor-secrets/$container_name"
    local output_dir="../bor-secrets/$container_name/dev"
    local output_file="$output_dir/${container_name}.development.env"
    
    echo "Processing $container_name..."
    
    # Check if source directory exists
    if [ ! -d "$source_dir" ]; then
        echo "  Warning: Source directory not found at $source_dir"
        echo "  Run copy-from-repos.sh first to copy environment files to ../bor-secrets"
        return 1
    fi
    
    # Check if output directory exists
    if [ ! -d "$output_dir" ]; then
        echo "  Warning: Output directory not found at $output_dir"
        echo "  Run copy-from-repos.sh first to create the directory structure"
        return 1
    fi
    
    # Check which source files exist
    local has_base_env=false
    local has_dev_env=false
    local has_dev_local_env=false
    
    [ -f "$source_dir/.env" ] && has_base_env=true
    [ -f "$source_dir/.env.development" ] && has_dev_env=true
    [ -f "$source_dir/.env.development.local" ] && has_dev_local_env=true
    
    if [ "$has_base_env" = false ] && [ "$has_dev_env" = false ]; then
        echo "  Warning: No base environment files found in $source_dir"
        return 1
    fi
    
    echo "  Creating amalgamated development environment file..."
    
    # Start with empty file
    > "$output_file"
    
    # Concatenate files in order: .env (base) -> .env.development (overrides) -> .env.development.local (final overrides)
    if [ "$has_base_env" = true ]; then
        echo "    Adding base .env file..."
        # Exclude files with 'example' in the name
        if [[ "$source_dir/.env" != *"example"* ]]; then
            cat "$source_dir/.env" >> "$output_file"
        else
            echo "      Skipping .env (contains 'example')"
        fi
    fi
    
    if [ "$has_dev_env" = true ]; then
        echo "    Adding .env.development overrides..."
        # Exclude files with 'example' in the name
        if [[ "$source_dir/.env.development" != *"example"* ]]; then
            cat "$source_dir/.env.development" >> "$output_file"
        else
            echo "      Skipping .env.development (contains 'example')"
        fi
    fi
    
    if [ "$has_dev_local_env" = true ]; then
        echo "    Adding .env.development.local final overrides..."
        # Exclude files with 'example' in the name
        if [[ "$source_dir/.env.development.local" != *"example"* ]]; then
            cat "$source_dir/.env.development.local" >> "$output_file"
        else
            echo "      Skipping .env.development.local (contains 'example')"
        fi
    fi
    
    # Set appropriate permissions (readable by owner only)
    chmod 600 "$output_file"
    
    # Count lines in output file
    local line_count=$(wc -l < "$output_file")
    
    echo "      ✓ Created $output_file with $line_count lines"
    echo "  ✓ Completed $container_name"
}

# Main execution
echo "Starting development environment file amalgamation..."
echo "Source: ../bor-secrets subdirectories (../bor-secrets/<container-name>)"
echo "Output: <container-name>.development.env in each ../bor-secrets/<container-name>/dev/ directory"
echo "Note: All files are created in the ../bor-secrets directory structure"
echo ""

# Process each container
for container in "${CONTAINERS[@]}"; do
    create_development_env "$container"
    echo ""
done

echo "Development environment file amalgamation completed!"
echo ""
echo "Files created in ../bor-secrets directories:"
for container in "${CONTAINERS[@]}"; do
    output_file="../bor-secrets/$container/dev/${container}.development.env"
    if [ -f "$output_file" ]; then
        line_count=$(wc -l < "$output_file")
        echo "  $output_file ($line_count lines)"
    fi
done
echo ""
echo "Next steps:"
echo "1. Review the amalgamated development.env files in ../bor-secrets directories"
echo "2. Use these files for local development and testing"
echo "3. Keep ../bor-secrets separate from git repositories"
echo "4. Run copy-from-repos.sh to update source files when needed" 