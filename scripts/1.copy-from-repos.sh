#!/bin/bash

# Script to copy environment files from bor- repositories into ../bor-secrets/pfcm and ../bor-secrets/base subdirectories
# This script copies .env* files from the parent directory repositories into the corresponding
# subdirectories in ../bor-secrets/pfcm and ../bor-secrets/base for centralized environment file management
# Note: ../bor-secrets is NOT a git repository and contains sensitive files

set -e  # Exit on any error

# Hard-coded container names for simplicity
CONTAINERS=(
    "bor-db"
    "bor-api"
    "bor-app"
    "bor-airflow"
    "bor-files"
    "bor-message"
)

# Function to copy env files from a repository
copy_env_files() {
    local container_name="$1"
    local source_dir="../$container_name"
    local pfcm_dir="../bor-secrets/pfcm/$container_name"
    local base_dir="../bor-secrets/base/$container_name"
    
    echo "Processing $container_name..."
    
    # Check if source repository exists
    if [ ! -d "$source_dir" ]; then
        echo "  Warning: Repository not found at $source_dir"
        return 1
    fi
    
    # Create target directory structures
    echo "  Creating target directory structure: $pfcm_dir"
    mkdir -p "$pfcm_dir"
    echo "  Creating target directory structure: $base_dir"
    mkdir -p "$base_dir"
    
    # Copy all .env* files to both pfcm and base directories
    local env_files=($(find "$source_dir" -maxdepth 1 -name ".env*" -type f))
    
    if [ ${#env_files[@]} -eq 0 ]; then
        echo "  No .env* files found in $source_dir"
        return 0
    fi
    
    echo "  Found ${#env_files[@]} environment file(s):"
    for env_file in "${env_files[@]}"; do
        local filename=$(basename "$env_file")
        local pfcm_file="$pfcm_dir/$filename"
        local base_file="$base_dir/$filename"
        
        echo "    Copying $filename..."
        
        # Copy to pfcm directory
        cp "$env_file" "$pfcm_file"
        chmod 600 "$pfcm_file"
        echo "      ✓ Copied to $pfcm_file"
        
        # Copy to base directory
        cp "$env_file" "$base_file"
        chmod 600 "$base_file"
        echo "      ✓ Copied to $base_file"
    done
    
    # Create production and development subdirectories in pfcm for future amalgamated files
    # Remove existing directories to ensure fresh timestamps
    rm -rf "$pfcm_dir/production"
    rm -rf "$pfcm_dir/development"
    mkdir -p "$pfcm_dir/production"
    mkdir -p "$pfcm_dir/development"
    
    echo "  ✓ Created production and development subdirectories in pfcm"
    echo "  ✓ Completed $container_name"
}

# Main execution
echo "Starting environment file copy process..."
echo "Source: parent directory repositories (../<container-name>)"
echo "Target: ../bor-secrets/pfcm and ../bor-secrets/base subdirectories"
echo "Note: ../bor-secrets is NOT a git repository and contains sensitive files"
echo ""

# Process each container
for container in "${CONTAINERS[@]}"; do
    copy_env_files "$container"
    echo ""
done

echo "Environment file copy process completed!"
echo ""
echo "Next steps:"
echo "1. Review the copied files in ../bor-secrets/pfcm and ../bor-secrets/base subdirectories"
echo "2. Run create-prod-envs.sh to generate production environment files"
echo "3. Run create-dev-envs.sh to generate development environment files"
echo "4. Use scp-prod-envs.sh to deploy to production server"
echo "5. Keep ../bor-secrets separate from git repositories"
