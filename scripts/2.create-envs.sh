#!/bin/bash

# Script to create amalgamated development and production environment files
# This script concatenates .env, .env.[development|production], and .env.[development|production].local files
# into single [development|production].env files in each container's /[development|production] subdirectory
# Note: Reads from ../bor-secrets/base and creates files in ../bor-secrets/pfcm (NOT in this git repo)
# Enhanced with envsubst for variable substitution and nested variable resolution
#
# KEY FEATURES:
# - Variable substitution using envsubst for nested variable resolution
# - Safe file processing with temporary files and proper cleanup
# - Handles missing files gracefully without errors
# - Creates both pfcm and base output directories
# - Maintains secure file permissions (600)
# - Creates both development and production environment files
# - Cleans output files by removing inline comments and trailing spaces
#
# VARIABLE SUBSTITUTION:
# This script can resolve nested variables like ${DB_HOST}:${DB_PORT}/${DB_NAME}
# Variables are processed in order: base -> [development|production] -> [development|production].local
# Each subsequent file can override variables from previous files
#
# PRODUCTION CONSIDERATIONS:
# - All files are processed with strict security (600 permissions)
# - Variable substitution ensures no unresolved references remain
# - Files are ready for immediate deployment to production servers

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

# Function to create amalgamated environment file for a specific environment
create_environment_env() {
    local container_name="$1"
    local environment="$2"  # "development" or "production"
    local source_dir="../bor-secrets/base/$container_name"
    local pfcm_output_dir="../bor-secrets/pfcm/$container_name/$environment"
    local base_output_dir="../bor-secrets/base/$container_name/$environment"
    local pfcm_output_file="$pfcm_output_dir/${container_name}.${environment}.env"
    local base_output_file="$base_output_dir/${container_name}.${environment}.env"
    
    echo "Processing $container_name for $environment environment..."
    
    # Check if source directory exists
    if [ ! -d "$source_dir" ]; then
        echo "  Warning: Source directory not found at $source_dir"
        echo "  Run copy-from-repos.sh first to copy environment files to ../bor-secrets/pfcm and base"
        return 1
    fi
    
    # Create environment directories if they don't exist
    if [ ! -d "$pfcm_output_dir" ]; then
        echo "  Creating pfcm output directory: $pfcm_output_dir"
        mkdir -p "$pfcm_output_dir"
    fi
    if [ ! -d "$base_output_dir" ]; then
        echo "  Creating base output directory: $base_output_dir"
        mkdir -p "$base_output_dir"
    fi
    
    # Check which source files exist
    local has_base_env=false
    local has_env_file=false
    local has_env_local_file=false
    
    [ -f "$source_dir/.env" ] && has_base_env=true
    [ -f "$source_dir/.env.$environment" ] && has_env_file=true
    [ -f "$source_dir/.env.$environment.local" ] && has_env_local_file=true
    
    if [ "$has_base_env" = false ] && [ "$has_env_file" = false ]; then
        echo "  Warning: No base environment files found in $source_dir"
        return 1
    fi
    
    echo "  Creating amalgamated $environment environment files..."
    
    # Create temporary working files for variable substitution
    # These temp files ensure safe processing and prevent corruption of source files
    local temp_base_file=$(mktemp)
    local temp_env_file=$(mktemp)
    local temp_env_local_file=$(mktemp)
    local temp_combined_file=$(mktemp)
    
    # Clean up temp files on exit - critical for security and disk space management
    trap 'rm -f "$temp_base_file" "$temp_env_file" "$temp_env_local_file" "$temp_combined_file" "$temp_cleaned_file"' EXIT
    
    # Start with empty combined file - will be populated with concatenated content
    > "$temp_combined_file"
    
    # Process base .env file first (foundation) - this provides the base configuration
    if [ "$has_base_env" = true ]; then
        echo "    Processing base .env file..."
        # Exclude files with 'example' in the name to avoid processing template files
        if [[ "$source_dir/.env" != *"example"* ]]; then
            # Copy base file to temp location for safe processing
            cp "$source_dir/.env" "$temp_base_file"
            # Append to combined file - order matters for variable precedence
            cat "$temp_base_file" >> "$temp_combined_file"
            echo "      ✓ Added base .env file"
        else
            echo "      Skipping .env (contains 'example')"
        fi
    fi
    
    # Process .env.[environment] file ([environment] overrides) - these override base values
    if [ "$has_env_file" = true ]; then
        echo "    Processing .env.$environment overrides..."
        # Exclude files with 'example' in the name to avoid processing template files
        if [[ "$source_dir/.env.$environment" != *"example"* ]]; then
            # Copy environment file to temp location for safe processing
            cp "$source_dir/.env.$environment" "$temp_env_file"
            # Append to combined file - environment values override base values
            cat "$temp_env_file" >> "$temp_combined_file"
            echo "      ✓ Added .env.$environment overrides"
        else
            echo "      Skipping .env.$environment (contains 'example')"
        fi
    fi
    
    # Process .env.[environment].local file (final local overrides) - highest precedence
    if [ "$has_env_local_file" = true ]; then
        echo "    Processing .env.$environment.local final overrides..."
        # Exclude files with 'example' in the name to avoid processing template files
        if [[ "$source_dir/.env.$environment.local" != *"example"* ]]; then
            # Copy local environment file to temp location for safe processing
            cp "$source_dir/.env.$environment.local" "$temp_env_local_file"
            # Append to combined file - local values have highest precedence
            cat "$source_dir/.env.$environment.local" >> "$temp_combined_file"
            echo "      ✓ Added .env.$environment.local final overrides"
        else
            echo "      Skipping .env.$environment.local (contains 'example')"
        fi
    fi
    
    # Clean the combined file by removing inline comments and trailing spaces
    # This ensures production-ready output files
    echo "    Cleaning combined file (removing inline comments and trailing spaces)..."
    local temp_cleaned_file=$(mktemp)
    trap 'rm -f "$temp_base_file" "$temp_env_file" "$temp_env_local_file" "$temp_combined_file" "$temp_cleaned_file"' EXIT
    
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        # Check if line is a variable assignment (contains =)
        if [[ "$line" =~ .*=.* ]]; then
            # This is a variable assignment line
            # Remove inline comments (everything after #) and trailing spaces
            cleaned_line=$(echo "$line" | sed 's/[[:space:]]*#.*$//' | sed 's/[[:space:]]*$//')
            # Only output if the cleaned line still contains an assignment
            if [[ "$cleaned_line" =~ .*=.* ]]; then
                echo "$cleaned_line" >> "$temp_cleaned_file"
            fi
        else
            # This is a comment line or other content - preserve as-is
            # Remove trailing spaces only
            cleaned_line=$(echo "$line" | sed 's/[[:space:]]*$//')
            echo "$cleaned_line" >> "$temp_cleaned_file"
        fi
    done < "$temp_combined_file"
    
    # Replace the combined file with the cleaned version
    mv "$temp_cleaned_file" "$temp_combined_file"
    echo "      ✓ Cleaned combined file (removed inline comments and trailing spaces)"
    
    # Now process the combined file with envsubst for variable substitution
    # This step resolves all nested variable references like ${DB_HOST}, ${DB_PORT}, etc.
    echo "    Processing variable substitutions with envsubst..."
    
    # Create a temporary environment file for envsubst processing
    # This file will be used to store the final processed environment
    local temp_env_export_file=$(mktemp)
    # Update trap to include the new temp file for cleanup
    trap 'rm -f "$temp_base_file" "$temp_env_file" "$temp_env_local_file" "$temp_combined_file" "$temp_env_export_file" "$temp_cleaned_file"' EXIT
    
    # Export all variables from the combined file for envsubst to use
    # This allows nested variable resolution by making variables available in shell environment
    set -a  # Automatically export all variables - critical for envsubst to work
    # Instead of sourcing the combined file (which can cause shell interpretation errors),
    # we'll use a safer approach with envsubst that processes variables without shell execution
    # First, create a clean environment file with only valid variable assignments
    # Filter out any lines that might contain shell commands or special characters
    # More strict filtering to avoid problematic lines
    grep -E '^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*$' "$temp_combined_file" > "$temp_env_export_file" 2>/dev/null || true
    
    # Also filter out lines with spaces in values or special characters that might cause issues
    # Create a more restrictive filter for the environment variables
    local temp_clean_env_file=$(mktemp)
    trap 'rm -f "$temp_base_file" "$temp_env_file" "$temp_env_local_file" "$temp_combined_file" "$temp_env_export_file" "$temp_clean_env_file"' EXIT
    
    # Only include simple variable assignments without spaces or special characters in values
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        # Only include lines that look like simple variable assignments
        if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*$ ]]; then
            echo "$line" >> "$temp_clean_env_file"
        fi
    done < "$temp_env_export_file"
    
    # Export only the clean variables for envsubst to use
    # This prevents shell interpretation errors while still allowing variable substitution
    if [ -s "$temp_clean_env_file" ]; then
        source "$temp_clean_env_file"
    fi
    set +a  # Turn off auto-export to prevent polluting shell environment
    
    # Use envsubst to process the combined file with variable substitution
    # This resolves nested variables like ${DB_HOST}, ${DB_PORT}, etc.
    # envsubst reads from stdin and writes processed output to stdout
    envsubst < "$temp_combined_file" > "$pfcm_output_file"
    envsubst < "$temp_combined_file" > "$base_output_file"
    
    # Set appropriate permissions (readable by owner only) - critical for security
    chmod 600 "$pfcm_output_file"
    chmod 600 "$base_output_file"
    
    # Count lines in output files for verification and debugging
    pfcm_line_count=$(wc -l < "$pfcm_output_file")
    base_line_count=$(wc -l < "$base_output_file")
    
    echo "      ✓ Created $pfcm_output_file with $pfcm_line_count lines"
    echo "      ✓ Created $base_output_file with $base_line_count lines"
    echo "      ✓ Variable substitution completed"
    echo "  ✓ Completed $container_name for $environment environment"
}

# Function to create both development and production environment files for a container
create_container_envs() {
    local container_name="$1"
    
    echo "Processing $container_name..."
    echo ""
    
    # Create development environment files
    create_environment_env "$container_name" "development"
    echo ""
    
    # Create production environment files
    create_environment_env "$container_name" "production"
    echo ""
    
    echo "✓ Completed $container_name (both environments)"
}

# Main execution
echo "Starting environment file amalgamation with variable substitution..."
echo "Source: ../bor-secrets/base subdirectories (../bor-secrets/base/<container-name>)"
echo "Output: /[development|production]/[development|production].env in each ../bor-secrets/pfcm container directory"
echo "Note: All files are created in ../bor-secrets/pfcm (NOT in this git repo)"
echo "Enhanced with envsubst for nested variable resolution"
echo "Creating both development and production environment files"
echo ""

# Process each container for both environments
for container in "${CONTAINERS[@]}"; do
    create_container_envs "$container"
    echo ""
done

echo "Environment file amalgamation completed!"
echo ""
echo "Files created in ../bor-secrets/pfcm:"
for container in "${CONTAINERS[@]}"; do
    # Development files
    dev_output_file="../bor-secrets/pfcm/$container/development/${container}.development.env"
    if [ -f "$dev_output_file" ]; then
        line_count=$(wc -l < "$dev_output_file")
        echo "  $dev_output_file ($line_count lines)"
    fi
    
    # Production files
    prod_output_file="../bor-secrets/pfcm/$container/production/${container}.production.env"
    if [ -f "$prod_output_file" ]; then
        line_count=$(wc -l < "$prod_output_file")
        echo "  $prod_output_file ($line_count lines)"
    fi
done
echo ""
echo "Files created in ../bor-secrets/base:"
for container in "${CONTAINERS[@]}"; do
    # Development files
    dev_output_file="../bor-secrets/base/$container/development/${container}.development.env"
    if [ -f "$dev_output_file" ]; then
        line_count=$(wc -l < "$dev_output_file")
        echo "  $dev_output_file ($line_count lines)"
    fi
    
    # Production files
    prod_output_file="../bor-secrets/base/$container/production/${container}.production.env"
    if [ -f "$prod_output_file" ]; then
        line_count=$(wc -l < "$prod_output_file")
        echo "  $prod_output_file ($line_count lines)"
    fi
done
echo ""
echo "Next steps:"
echo "1. Review the amalgamated environment files in ../bor-secrets/pfcm and base"
echo "2. Use rsync-prod-envs.sh to deploy production files to servers"
echo "3. Use development files for local development and testing"
echo "4. Keep ../bor-secrets separate from git repositories"
echo "5. Run copy-from-repos.sh to update source files when needed"
echo "6. Variable substitution now supports nested references (e.g., ${DB_HOST}:${DB_PORT})"
echo "7. Output files are cleaned (inline comments and trailing spaces removed)"
