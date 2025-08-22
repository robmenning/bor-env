#!/bin/bash

# Script to rsync production environment files to the selected server
# This script copies the entire contents of ../bor-secrets/ directory to the server
# excluding .env* files for security

set -e  # Exit on any error

# Server configurations
declare -A SERVER_HOSTS
declare -A SERVER_USERS
declare -A SERVER_PATHS

# ionos server configuration
SERVER_HOSTS["ionos"]="xenodochial-turing.108-175-7-118.plesk.page"
SERVER_USERS["ionos"]="robmenning.com"
SERVER_PATHS["ionos"]="/var/www/vhosts/robmenning.com/bor/bor-secrets"

# az-bor-dev-vm server configuration
SERVER_HOSTS["az-bor-dev-vm"]="4.206.67.169"
SERVER_USERS["az-bor-dev-vm"]="boradmin"
SERVER_PATHS["az-bor-dev-vm"]="/opt/bor/containers/bor-secrets"

# Hard-coded container names for simplicity (same as create-prod-envs.sh)
CONTAINERS=(
    "bor-db"
    "bor-api"
    "bor-app"
    "bor-airflow"
    "bor-files"
    "bor-message"
)

# Function to check if server name is valid
is_valid_server() {
    local server_name="$1"
    if [[ -n "${SERVER_HOSTS[$server_name]}" ]]; then
        return 0
    fi
    return 1
}

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

# Function to rsync entire bor-secrets directory to server
rsync_bor_secrets() {
    local server_name="$1"
    local local_dir="../bor-secrets"
    local remote_path="${SERVER_USERS[$server_name]}@${SERVER_HOSTS[$server_name]}:${SERVER_PATHS[$server_name]}"
    
    echo "Processing bor-secrets directory..."
    
    # Check if local directory exists
    if [ ! -d "$local_dir" ]; then
        echo "  Error: Local directory not found at $local_dir"
        echo "  Run copy-from-repos.sh first to create the bor-secrets directory structure"
        return 1
    fi
    
    echo "  Copying entire bor-secrets directory to server..."
    echo "  Source: $local_dir"
    echo "  Destination: $remote_path"
    echo "  Excluding: .env* files"
    
    # Create remote directory if it doesn't exist
    echo "    Creating remote directory structure..."
    ssh "${SERVER_USERS[$server_name]}@${SERVER_HOSTS[$server_name]}" "mkdir -p ${SERVER_PATHS[$server_name]}"
    
    # Rsync entire directory excluding .env* files
    echo "    Uploading files..."
    rsync -avz --progress --exclude='*.env*' "$local_dir/" "$remote_path/"
    
    echo "      ✓ Directory contents copied to server"
    echo "  ✓ Completed bor-secrets sync"
}

# Function to rsync specific container directory to server
rsync_container() {
    local server_name="$1"
    local container_name="$2"
    local local_dir="../bor-secrets/pfcm/$container_name"
    local remote_path="${SERVER_USERS[$server_name]}@${SERVER_HOSTS[$server_name]}:${SERVER_PATHS[$server_name]}/pfcm/$container_name"
    
    echo "Processing $container_name..."
    
    # Check if local directory exists
    if [ ! -d "$local_dir" ]; then
        echo "  Warning: Local directory not found at $local_dir"
        echo "  Run copy-from-repos.sh first to create the bor-secrets directory structure"
        return 1
    fi
    
    echo "  Copying $container_name directory to server..."
    echo "  Source: $local_dir"
    echo "  Destination: $remote_path"
    echo "  Excluding: .env* files"
    
    # Create remote directory if it doesn't exist
    echo "    Creating remote directory structure..."
    ssh "${SERVER_USERS[$server_name]}@${SERVER_HOSTS[$server_name]}" "mkdir -p ${SERVER_PATHS[$server_name]}/pfcm/$container_name"
    
    # Rsync container directory excluding .env* files
    echo "    Uploading files..."
    rsync -avz --progress --exclude='*.env*' "$local_dir/" "$remote_path/"
    
    echo "      ✓ Container directory copied to server"
    echo "  ✓ Completed $container_name"
}

# Function to display usage
show_usage() {
    echo "Usage: $0 <server-name> [container-name]"
    echo ""
    echo "Arguments:"
    echo "  server-name    Required: Server to deploy to (ionos|az-bor-dev-vm)"
    echo "  container-name Optional: Specific container to deploy (default: all containers)"
    echo ""
    echo "Examples:"
    echo "  $0 ionos                    # Deploy all containers to ionos server"
    echo "  $0 az-bor-dev-vm bor-app   # Deploy only bor-app to az-bor-dev-vm server"
    echo ""
    echo "Valid servers: ionos, az-bor-dev-vm"
    echo "Valid containers: ${CONTAINERS[*]}"
    echo ""
    echo "Note: This script rsyncs the entire bor-secrets directory structure"
    echo "      excluding .env* files for security"
}

# Main execution
# Check command line arguments
if [ $# -lt 1 ]; then
    echo "Error: Server name is required"
    show_usage
    exit 1
fi

SERVER_NAME="$1"
shift  # Remove server name from arguments

# Validate server name
if ! is_valid_server "$SERVER_NAME"; then
    echo "Error: Invalid server name '$SERVER_NAME'"
    echo "Valid servers: ${!SERVER_HOSTS[*]}"
    show_usage
    exit 1
fi

# Check command line arguments for container
if [ $# -eq 1 ]; then
    # Single container specified
    CONTAINER_NAME="$1"
    if ! is_valid_container "$CONTAINER_NAME"; then
        echo "Error: Invalid container name '$CONTAINER_NAME'"
        echo "Valid containers: ${CONTAINERS[*]}"
        show_usage
        exit 1
    fi
    # Deploy single container
    echo "Deploying single container: $CONTAINER_NAME"
    rsync_container "$SERVER_NAME" "$CONTAINER_NAME"
elif [ $# -gt 1 ]; then
    echo "Error: Too many arguments"
    show_usage
    exit 1
else
    # No container specified - confirm deployment of all containers
    get_confirmation
    rsync_bor_secrets "$SERVER_NAME"
fi

echo ""
echo "Production environment file deployment completed!"
echo ""
echo "Files deployed to server:"
echo "  ${SERVER_PATHS[$SERVER_NAME]}"
echo ""
echo "Next steps:"
if [ $# -eq 1 ]; then
    echo "1. Test the deployment with the single container: $CONTAINER_NAME"
else
    echo "1. Test the deployment with a single container first"
fi
echo "2. Update your Docker run commands to use --env-file with these server paths"
echo "3. Restart your production containers with the new environment files"
