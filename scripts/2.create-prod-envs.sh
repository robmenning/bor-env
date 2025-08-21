#!/bin/bash

# Script to create amalgamated production environment files
# This script concatenates .env, .env.production, and .env.production.local files
# into a single production.env file in each container's /production subdirectory
# Note: Reads from ../bor-secrets/base and creates files in ../bor-secrets/pfcm (NOT in this git repo)
# Enhanced with envsubst for variable substitution and nested variable resolution
#
# KEY FEATURES:
# - Variable substitution using envsubst for nested variable resolution
# - Safe file processing with temporary files and proper cleanup
# - Handles missing files gracefully without errors
# - Creates both pfcm and base output directories
# - Maintains secure file permissions (600)
#
# VARIABLE SUBSTITUTION:
# This script can resolve nested variables like ${DB_HOST}:${DB_PORT}/${DB_NAME}
# Variables are processed in order: base -> production -> production.local
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

# Function to create amalgamated production env file
create_production_env() {
    local container_name="$1"
    local source_dir="../bor-secrets/base/$container_name"
    local pfcm_output_dir="../bor-secrets/pfcm/$container_name/production"
    local base_output_dir="../bor-secrets/base/$container_name/production"
    local pfcm_output_file="$pfcm_output_dir/${container_name}.production.env"
    local base_output_file="$base_output_dir/${container_name}.production.env"
    
    echo "Processing $container_name..."
    
    # Check if source directory exists
    if [ ! -d "$source_dir" ]; then
        echo "  Warning: Source directory not found at $source_dir"
        echo "  Run copy-from-repos.sh first to copy environment files to ../bor-secrets/pfcm and base"
        return 1
    fi
    
    # Create production directories if they don't exist
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
    local has_prod_env=false
    local has_prod_local_env=false
    
    [ -f "$source_dir/.env" ] && has_base_env=true
    [ -f "$source_dir/.env.production" ] && has_prod_env=true
    [ -f "$source_dir/.env.production.local" ] && has_prod_local_env=true
    
    if [ "$has_base_env" = false ] && [ "$has_prod_env" = false ]; then
        echo "  Warning: No base environment files found in $source_dir"
        return 1
    fi
    
    echo "  Creating amalgamated production environment files..."
    
    # Create temporary working files for variable substitution
    # These temp files ensure safe processing and prevent corruption of source files
    local temp_base_file=$(mktemp)
    local temp_prod_file=$(mktemp)
    local temp_prod_local_file=$(mktemp)
    local temp_combined_file=$(mktemp)
    
    # Clean up temp files on exit - critical for security and disk space management
    trap 'rm -f "$temp_base_file" "$temp_prod_file" "$temp_prod_local_file" "$temp_combined_file"' EXIT
    
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
    
    # Process .env.production file (production overrides) - these override base values
    if [ "$has_prod_env" = true ]; then
        echo "    Processing .env.production overrides..."
        # Exclude files with 'example' in the name to avoid processing template files
        if [[ "$source_dir/.env.production" != *"example"* ]]; then
            # Copy production file to temp location for safe processing
            cp "$source_dir/.env.production" "$temp_prod_file"
            # Append to combined file - development values override base values
            cat "$temp_prod_file" >> "$temp_combined_file"
            echo "      ✓ Added .env.production overrides"
        else
            echo "      Skipping .env.production (contains 'example')"
        fi
    fi
    
    # Process .env.production.local file (final local overrides) - highest precedence
    if [ "$has_prod_local_env" = true ]; then
        echo "    Processing .env.production.local final overrides..."
        # Exclude files with 'example' in the name to avoid processing template files
        if [[ "$source_dir/.env.production.local" != *"example"* ]]; then
            # Copy local production file to temp location for safe processing
            cp "$source_dir/.env.production.local" "$temp_prod_local_file"
            # Append to combined file - local values have highest precedence
            cat "$source_dir/.env.production.local" >> "$temp_combined_file"
            echo "      ✓ Added .env.production.local final overrides"
        else
            echo "      Skipping .env.production.local (contains 'example')"
        fi
    fi
    
    # Now process the combined file with envsubst for variable substitution
    # This step resolves all nested variable references like ${DB_HOST}, ${DB_PORT}, etc.
    echo "    Processing variable substitutions with envsubst..."
    
    # Create a temporary environment file for envsubst processing
    # This file will be used to store the final processed environment
    local temp_env_file=$(mktemp)
    # Update trap to include the new temp file for cleanup
    trap 'rm -f "$temp_base_file" "$temp_prod_file" "$temp_prod_local_file" "$temp_combined_file" "$temp_env_file"' EXIT
    
    # Export all variables from the combined file for envsubst to use
    # This allows nested variable resolution by making variables available in shell environment
    set -a  # Automatically export all variables - critical for envsubst to work
    # Instead of sourcing the combined file (which can cause shell interpretation errors),
    # we'll use a safer approach with envsubst that processes variables without shell execution
    # First, create a clean environment file with only valid variable assignments
    # Filter out any lines that might contain shell commands or special characters
    # More strict filtering to avoid problematic lines
    grep -E '^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*$' "$temp_combined_file" > "$temp_env_file" 2>/dev/null || true
    
    # Also filter out lines with spaces in values or special characters that might cause issues
    # Create a more restrictive filter for the environment variables
    local temp_clean_env_file=$(mktemp)
    trap 'rm -f "$temp_base_file" "$temp_prod_file" "$temp_prod_local_file" "$temp_combined_file" "$temp_env_file" "$temp_clean_env_file"' EXIT
    
    # Only include simple variable assignments without spaces or special characters in values
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        # Only include lines that look like simple variable assignments
        if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*$ ]]; then
            echo "$line" >> "$temp_clean_env_file"
        fi
    done < "$temp_env_file"
    
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
    echo "  ✓ Completed $container_name"
}

# Main execution
echo "Starting production environment file amalgamation with variable substitution..."
echo "Source: ../bor-secrets/base subdirectories (../bor-secrets/base/<container-name>)"
echo "Output: /production/production.env in each ../bor-secrets/pfcm container directory"
echo "Note: All files are created in ../bor-secrets/pfcm (NOT in this git repo)"
echo "Enhanced with envsubst for nested variable resolution"
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
echo "Files created in ../bor-secrets/base:"
for container in "${CONTAINERS[@]}"; do
    output_file="../bor-secrets/base/$container/production/${container}.production.env"
    if [ -f "$output_file" ]; then
        line_count=$(wc -l < "$output_file")
        echo "  $output_file ($line_count lines)"
    fi
done
echo ""
echo "Next steps:"
echo "1. Review the amalgamated production.env files in ../bor-secrets/pfcm and base"
echo "2. Use scp-prod-envs.sh to deploy these files to production server"
echo "3. Keep ../bor-secrets separate from git repositories"
echo "4. Run copy-from-repos.sh to update source files when needed"
echo "5. Variable substitution now supports nested references (e.g., ${DB_HOST}:${DB_PORT})"
