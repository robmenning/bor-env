#!/bin/bash

# Script to create amalgamated production environment files
# This script concatenates .env, .env.production, and .env.production.local files
# into a single production.env file in each container's /production subdirectory
# Note: Reads from ../bor-secrets/base and creates files in ../bor-secrets/pfcm (NOT in this git repo)

set -e  # Exit on any error

# Hard-coded container names for simplicity (same as copy-from-repos.sh)
CONTAINERS=(
    "bor-db"
    "bor-api"
    "bor-app"
    "bor-airflow"
    "bor-files"
    "bor-message"
)

# Function to create amalgamated production env file
create_production_env() {
    local container_name="$1"
    local source_dir="../bor-secrets/base/$container_name"
    local output_dir="../bor-secrets/pfcm/$container_name/production"
    local output_file="$output_dir/${container_name}.production.env"
    
    echo "Processing $container_name..."
    
    # Check if source directory exists
    if [ ! -d "$source_dir" ]; then
        echo "  Warning: Source directory not found at $source_dir"
        echo "  Run copy-from-repos.sh first to copy environment files to ../bor-secrets/pfcm"
        echo "  Then copy pfcm to base: cp -r ../bor-secrets/pfcm/* ../bor-secrets/base/"
        return 1
    fi
    
    # Create production directory if it doesn't exist
    if [ ! -d "$output_dir" ]; then
        echo "  Creating output directory: $output_dir"
        mkdir -p "$output_dir"
    fi
    
    # Check which source files exist
    local has_base_env=false
    local has_prod_env=false
    local has_prod_local_env=false
    
    [ -f "$source_dir/.env" ] && has_base_env=true
    [ -f "$source_dir/.env.production" ] && has_prod_env=true
    [ -f "$source_dir/.env.production.local" ] && has_prod_local_env=true
    
    if [ "$has_base_env" = false ] && [ "$has_prod_env" = false ]; then
        echo "  Warning: No base environment files found in $source_dir"
        return 1
    fi
    
    echo "  Creating amalgamated production environment file..."
    
    # Start with empty file
    > "$output_file"
    
    # Concatenate files in order: .env (base) -> .env.production (overrides) -> .env.production.local (final overrides)
    if [ "$has_base_env" = true ]; then
        echo "    Adding base .env file..."
        # Exclude files with 'example' in the name
        if [[ "$source_dir/.env" != *"example"* ]]; then
            cat "$source_dir/.env" >> "$output_file"
        else
            echo "      Skipping .env (contains 'example')"
        fi
    fi
    
    if [ "$has_prod_env" = true ]; then
        echo "    Adding .env.production overrides..."
        # Exclude files with 'example' in the name
        if [[ "$source_dir/.env.production" != *"example"* ]]; then
            cat "$source_dir/.env.production" >> "$output_file"
        else
            echo "      Skipping .env.production (contains 'example')"
        fi
    fi
    
    if [ "$has_prod_local_env" = true ]; then
        echo "    Adding .env.production.local final overrides..."
        # Exclude files with 'example' in the name
        if [[ "$source_dir/.env.production.local" != *"example"* ]]; then
            cat "$source_dir/.env.production.local" >> "$output_file"
        else
            echo "      Skipping .env.production.local (contains 'example')"
        fi
    fi
    
    # Set appropriate permissions (readable by owner only)
    chmod 600 "$output_file"
    
    # Count lines in output file
    line_count=$(wc -l < "$output_file")
    
    echo "      ✓ Created $output_file with $line_count lines"
    echo "  ✓ Completed $container_name"
}

# Main execution
echo "Starting production environment file amalgamation..."
echo "Source: ../bor-secrets/base subdirectories (../bor-secrets/base/<container-name>)"
echo "Output: /production/production.env in each ../bor-secrets/pfcm container directory"
echo "Note: All files are created in ../bor-secrets/pfcm (NOT in this git repo)"
echo ""

# Process each container
for container in "${CONTAINERS[@]}"; do
    create_production_env "$container"
    echo ""
done

echo "Production environment file amalgamation completed!"
echo ""
echo "Files created in ../bor-secrets/pfcm:"
for container in "${CONTAINERS[@]}"; do
    output_file="../bor-secrets/pfcm/$container/production/${container}.production.env"
    if [ -f "$output_file" ]; then
        line_count=$(wc -l < "$output_file")
        echo "  $output_file ($line_count lines)"
    fi
done
echo ""
echo "Next steps:"
echo "1. Review the amalgamated production.env files in ../bor-secrets/pfcm"
echo "2. Use scp-prod-envs.sh to deploy these files to production server"
echo "3. Keep ../bor-secrets separate from git repositories"
echo "4. Run copy-from-repos.sh to update source files when needed"
