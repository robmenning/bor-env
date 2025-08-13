#!/bin/bash

# Script to copy environment files from bor- repositories into ../bor-secrets subdirectories
# This script copies .env* files from the parent directory repositories into the corresponding
# subdirectories in ../bor-secrets for centralized environment file management
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
    local target_dir="../bor-secrets/$container_name"
    
    echo "Processing $container_name..."
    
    # Check if source repository exists
    if [ ! -d "$source_dir" ]; then
        echo "  Warning: Repository not found at $source_dir"
        return 1
    fi
    
    # Check if target directory exists
    if [ ! -d "$target_dir" ]; then
        echo "  Creating target directory: $target_dir"
        mkdir -p "$target_dir"
    fi
    
    # Copy all .env* files
    local env_files=($(find "$source_dir" -maxdepth 1 -name ".env*" -type f))
    
    if [ ${#env_files[@]} -eq 0 ]; then
        echo "  No .env* files found in $source_dir"
        return 0
    fi
    
    echo "  Found ${#env_files[@]} environment file(s):"
    for env_file in "${env_files[@]}"; do
        local filename=$(basename "$env_file")
        local target_file="$target_dir/$filename"
        
        echo "    Copying $filename..."
        cp "$env_file" "$target_file"
        
        # Set appropriate permissions (readable by owner only)
        chmod 600 "$target_file"
        
        echo "      ✓ Copied to $target_file"
    done
    
    echo "  ✓ Completed $container_name"
}

# Main execution
echo "Starting environment file copy process..."
echo "Source: parent directory repositories (../<container-name>)"
echo "Target: ../bor-secrets subdirectories (../bor-secrets/<container-name>)"
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
echo "1. Review the copied files in ../bor-secrets subdirectories"
echo "2. Run create-prod-envs.sh to generate production environment files"
echo "3. Use scp-prod-envs.sh to deploy to production server"
echo "4. Keep ../bor-secrets separate from git repositories"
