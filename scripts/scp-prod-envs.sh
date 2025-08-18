#!/bin/bash

# Script to scp production environment files to the production server
# This script copies the amalgamated production.env files from ../bor-secrets prod directories
# to the server secrets directory for deployment

# server path to scp to:
# robmenning.com@xenodochial-turing.108-175-7-118.plesk.page:/var/www/vhosts/robmenning.com/bor/bor-secrets

set -e  # Exit on any error

# Server configuration
SERVER_HOST="xenodochial-turing.108-175-7-118.plesk.page"  # Server hostname from header comments
SERVER_USER="robmenning.com"      # Username from header comments
SERVER_PATH="/var/www/vhosts/robmenning.com/bor/bor-secrets"  # Server path for all env files

# Hard-coded container names for simplicity (same as create-prod-envs.sh)
CONTAINERS=(
    "bor-db"
    "bor-api"
    "bor-app"
    "bor-airflow"
    "bor-files"
    "bor-message"
)

# Function to check if container name is valid
is_valid_container() {
    local container_name="$1"
    for container in "${CONTAINERS[@]}"; do
        if [[ "$container" == "$container_name" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to get confirmation from user
get_confirmation() {
    echo "No container specified. This will deploy ALL containers."
    echo "Are you sure you want to continue? (y/N): "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        echo "Deployment cancelled."
        exit 0
    fi
}

# Function to scp production env file to server
scp_production_env() {
    local container_name="$1"
    local local_file="../bor-secrets/$container_name/prod/${container_name}.production.env"
    local remote_file="${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}/${container_name}/prod/${container_name}.production.env"
    
    echo "Processing $container_name..."
    
    # Check if local file exists
    if [ ! -f "$local_file" ]; then
        echo "  Warning: Local file not found at $local_file"
        echo "  Run create-prod-envs.sh first to generate the production environment files in ../bor-secrets/prod directories"
        return 1
    fi
    
    echo "  Copying ${container_name}.production.env to server..."
    
    # Copy file to server
    echo "    Uploading file..."
    scp "$local_file" "$remote_file"
    
    echo "      ✓ File copied to server"
    
    echo "  ✓ Completed $container_name"
}

# Main execution
# Check command line arguments
if [ $# -eq 1 ]; then
    # Single container specified
    CONTAINER_NAME="$1"
    if ! is_valid_container "$CONTAINER_NAME"; then
        echo "Error: Invalid container name '$CONTAINER_NAME'"
        echo "Valid containers: ${CONTAINERS[*]}"
        echo "Usage: $0 [container-name]"
        echo "  If no container is specified, all containers will be deployed (with confirmation)"
        exit 1
    fi
    # Override CONTAINERS array with single container
    CONTAINERS=("$CONTAINER_NAME")
    echo "Deploying single container: $CONTAINER_NAME"
elif [ $# -gt 1 ]; then
    echo "Error: Too many arguments"
    echo "Usage: $0 [container-name]"
    echo "  If no container is specified, all containers will be deployed (with confirmation)"
    exit 1
else
    # No arguments - confirm deployment of all containers
    get_confirmation
fi

echo "Starting production environment file deployment to server..."
echo "Server: ${SERVER_USER}@${SERVER_HOST}"
echo "Target path: ${SERVER_PATH}"
echo "Source: ../bor-secrets prod directories"
echo "Note: You will be prompted for password for each file transfer"
echo ""

# Note: Using scp for file transfer (no SSH connection test)
echo "Note: You will be prompted for password for each file transfer"
echo ""

# Process containers (either single or all)
for container in "${CONTAINERS[@]}"; do
    scp_production_env "$container"
    echo ""
done

echo "Production environment file deployment completed!"
echo ""
echo "Files deployed to server:"
for container in "${CONTAINERS[@]}"; do
    local_file="../bor-secrets/$container/prod/${container}.production.env"
    if [ -f "$local_file" ]; then
        echo "  ${SERVER_PATH}/${container}/prod/${container}.production.env"
    fi
done
echo ""
echo "Next steps:"
if [ ${#CONTAINERS[@]} -eq 1 ]; then
    echo "1. Test the deployment with the single container: ${CONTAINERS[0]}"
else
    echo "1. Test the deployment with a single container first"
fi
echo "2. Update your Docker run commands to use --env-file with these server paths"
echo "3. Restart your production containers with the new environment files"
