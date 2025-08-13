#!/bin/bash

# Script to scp production environment files to the production server
# This script copies the amalgamated production.env files from prod-out directories
# to the server secrets directory for deployment

# server path to scp to:
# robmenning.com@xenodochial-turing.108-175-7-118.plesk.page:/var/www/vhosts/robmenning.com/bor/secrets

set -e  # Exit on any error

# Server configuration
SERVER_HOST="xenodochial-turing.108-175-7-118.plesk.page"  # Server hostname from header comments
SERVER_USER="robmenning.com"      # Username from header comments
SERVER_PATH="/var/www/vhosts/robmenning.com/bor/secrets"  # Server path from header comments

# Hard-coded container names for simplicity (same as create-prod-envs.sh)
CONTAINERS=(
    "bor-db"
    "bor-api"
    "bor-app"
    "bor-airflow"
    "bor-files"
    "bor-message"
)

# Function to scp production env file to server
scp_production_env() {
    local container_name="$1"
    local local_file="./$container_name/prod-out/${container_name}.production.env"
    local remote_file="${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}/${container_name}.production.env"
    
    echo "Processing $container_name..."
    
    # Check if local file exists
    if [ ! -f "$local_file" ]; then
        echo "  Warning: Local file not found at $local_file"
        echo "  Run create-prod-envs.sh first to generate the production environment files"
        return 1
    fi
    
    echo "  Copying ${container_name}.production.env to server..."
    
    # Create remote directory if it doesn't exist
    echo "    Creating remote directory if needed..."
    ssh "${SERVER_USER}@${SERVER_HOST}" "mkdir -p ${SERVER_PATH}"
    
    # Copy file to server
    echo "    Uploading file..."
    scp "$local_file" "$remote_file"
    
    # Set appropriate permissions on server
    echo "    Setting permissions on server..."
    ssh "${SERVER_USER}@${SERVER_HOST}" "chmod 600 ${SERVER_PATH}/${container_name}.production.env"
    
    # Verify file was copied
    local remote_size=$(ssh "${SERVER_USER}@${SERVER_HOST}" "wc -c < ${SERVER_PATH}/${container_name}.production.env")
    local local_size=$(wc -c < "$local_file")
    
    if [ "$remote_size" -eq "$local_size" ]; then
        echo "      ✓ Successfully copied to server (${remote_size} bytes)"
    else
        echo "      ✗ File size mismatch: local ${local_size} bytes, remote ${remote_size} bytes"
        return 1
    fi
    
    echo "  ✓ Completed $container_name"
}

# Main execution
echo "Starting production environment file deployment to server..."
echo "Server: ${SERVER_USER}@${SERVER_HOST}"
echo "Target path: ${SERVER_PATH}"
echo "Note: You will be prompted for password for each file transfer"
echo ""

# Check if we have SSH access
echo "Testing SSH connection..."
if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "${SERVER_USER}@${SERVER_HOST}" "echo 'SSH connection successful'" >/dev/null 2>&1; then
    echo "Note: SSH key authentication not available, will use password authentication"
    echo "You will be prompted for password for each operation"
fi
echo ""

# Process each container
for container in "${CONTAINERS[@]}"; do
    scp_production_env "$container"
    echo ""
done

echo "Production environment file deployment completed!"
echo ""
echo "Files deployed to server:"
for container in "${CONTAINERS[@]}"; do
    local local_file="./$container/prod-out/${container}.production.env"
    if [ -f "$local_file" ]; then
        echo "  ${SERVER_PATH}/${container}.production.env"
    fi
done
echo ""
echo "Next steps:"
echo "1. Update your Docker run commands to use --env-file with these server paths"
echo "2. Test the deployment with a single container first"
echo "3. Restart your production containers with the new environment files"
