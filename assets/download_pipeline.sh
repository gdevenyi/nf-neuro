#!/bin/bash

# Script to pre-download Nextflow pipeline and Apptainer/Singularity containers
# for offline execution

set -euo pipefail

# Default values
REVISION="main"
PARALLEL_DOWNLOADS=4
CONTAINER_DIR="./containers"
CACHE_DIR="./singularity_cache"
PIPELINE=""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Help message
usage() {
    cat << EOF
Usage: $(basename "$0") -p PIPELINE [OPTIONS]

Pre-download Nextflow pipeline and Apptainer/Singularity containers for offline use.

In order to download the containers, this script requires:
 - nextflow
 - apptainer or singularity
 - jq
 - GNU parallel (optional, for parallel downloads)

Required arguments:
    -p PIPELINE         Pipeline name (e.g., scilus/sf-pediatric or nf-core/rnaseq)

Optional arguments:
    -r REVISION         Pipeline revision/version (default: main)
    -d DOWNLOADS        Number of parallel container downloads (default: 4)
    -o OUTPUT_DIR       Container output directory (default: ./containers)
    -c CACHE_DIR        Singularity/Apptainer cache directory (default: ./singularity_cache)
    -h                  Show this help message

Example:
    $(basename "$0") -p scilus/sf-pediatric -r 0.2.1 -d 8 -o /path/to/containers -c /path/to/cache

EOF
    exit 1
}

# Parse command line arguments
while getopts "p:r:d:o:c:h" opt; do
    case $opt in
        p) PIPELINE="$OPTARG" ;;
        r) REVISION="$OPTARG" ;;
        d) PARALLEL_DOWNLOADS="$OPTARG" ;;
        o) CONTAINER_DIR="$OPTARG" ;;
        c) CACHE_DIR="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Check required arguments
if [ -z "$PIPELINE" ]; then
    echo -e "${RED}Error: Pipeline name is required${NC}"
    usage
fi

# Validate parallel downloads is a number
if ! [[ "$PARALLEL_DOWNLOADS" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: Number of parallel downloads must be a positive integer${NC}"
    exit 1
fi

# Validate required tools
echo -e "${YELLOW}Validating required tools...${NC}"

if ! command -v nextflow &> /dev/null; then
    echo -e "${RED}Error: nextflow is not installed or not in PATH${NC}"
    echo "Please install Nextflow: https://www.nextflow.io/docs/latest/getstarted.html"
    exit 1
fi

if ! command -v apptainer &> /dev/null && ! command -v singularity &> /dev/null; then
    echo -e "${RED}Error: Neither apptainer nor singularity is installed or in PATH${NC}"
    echo "Please install Apptainer: https://apptainer.org/docs/user/main/quick_start.html"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed or not in PATH${NC}"
    echo "Please install jq: https://stedolan.github.io/jq/download/"
    exit 1
fi

echo -e "${GREEN}✓ All required tools are available${NC}"
echo ""

echo -e "${GREEN}=== Nextflow Pipeline Offline Downloader ===${NC}"
echo "Pipeline: $PIPELINE"
echo "Revision: $REVISION"
echo "Parallel downloads: $PARALLEL_DOWNLOADS"
echo "Container directory: $CONTAINER_DIR"
echo "Cache directory: $CACHE_DIR"
echo ""

# Create container and cache directories
mkdir -p "$CONTAINER_DIR"
mkdir -p "$CACHE_DIR"
CONTAINER_DIR=$(realpath "$CONTAINER_DIR")
CACHE_DIR=$(realpath "$CACHE_DIR")

# Set Apptainer/Singularity cache directory
export APPTAINER_CACHEDIR="$CACHE_DIR"
export SINGULARITY_CACHEDIR="$CACHE_DIR"

# Step 1: Pull the Nextflow pipeline
echo -e "${YELLOW}Step 1: Pulling Nextflow pipeline...${NC}"
if nextflow pull "$PIPELINE" -r "$REVISION"; then
    echo -e "${GREEN}✓ Pipeline pulled successfully${NC}"
else
    echo -e "${RED}✗ Failed to pull pipeline${NC}"
    exit 1
fi
echo ""

# Step 2: Inspect pipeline and extract container information
echo -e "${YELLOW}Step 2: Inspecting pipeline for container requirements...${NC}"
INSPECT_JSON=$(mktemp)
if nextflow inspect "$PIPELINE" -r "$REVISION" -format json > "$INSPECT_JSON"; then
    echo -e "${GREEN}✓ Pipeline inspection complete${NC}"
else
    echo -e "${RED}✗ Failed to inspect pipeline${NC}"
    rm -f "$INSPECT_JSON"
    exit 1
fi

# Extract unique container URLs
CONTAINERS=$(jq -r '.processes[].container' "$INSPECT_JSON" 2>/dev/null | sort -u | grep -v "^null$" || true)
CONTAINER_COUNT=$(echo "$CONTAINERS" | grep -v "^$" | wc -l)

if [ "$CONTAINER_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠ No containers found in pipeline${NC}"
    rm -f "$INSPECT_JSON"
    exit 0
fi

echo -e "${GREEN}✓ Found $CONTAINER_COUNT unique container(s)${NC}"
echo ""

# Step 3: Download containers
echo -e "${YELLOW}Step 3: Downloading Apptainer/Singularity containers...${NC}"
echo "This may take a while depending on container sizes..."
echo ""

# Function to download a single container
download_container() {
    local container_url="$1"
    local container_dir="$2"
    local index="$3"
    local total="$4"

    # Convert Docker URL to appropriate format for Apptainer
    local apptainer_url="$container_url"

    # Extract a safe filename from the container URL with docker.io- prefix
    # Remove docker:// prefix if present
    local clean_url=$(echo "$container_url" | sed 's|^docker://||g')

    # Add docker.io/ prefix if not already present (for docker hub images)
    if [[ ! "$clean_url" =~ ^[^/]+\.[^/]+/ ]]; then
        # No domain in URL, assume docker.io
        clean_url="docker.io/$clean_url"
    fi

    # Convert to filename: replace / with - and : with -
    local container_name=$(echo "$clean_url" | sed 's|/|-|g' | sed 's|:|-|g')
    local output_file="$container_dir/${container_name}.img"

    # Check if container already exists
    if [ -f "$output_file" ]; then
        echo "[$index/$total] ✓ Already exists: $container_name"
        return 0
    fi

    echo "[$index/$total] Downloading: $container_url"

    # Download with apptainer/singularity
    local cmd="apptainer"
    if ! command -v apptainer &> /dev/null; then
        if command -v singularity &> /dev/null; then
            cmd="singularity"
        else
            echo "[$index/$total] ✗ Error: Neither apptainer nor singularity found"
            return 1
        fi
    fi

    # Use docker:// prefix if not already present
    if [[ ! "$apptainer_url" =~ ^docker:// ]] && [[ ! "$apptainer_url" =~ ^oras:// ]] && [[ ! "$apptainer_url" =~ ^shub:// ]]; then
        apptainer_url="docker://$apptainer_url"
    fi

    # Capture output for error reporting only
    local error_log=$(mktemp)
    if $cmd pull --disable-cache "$output_file" "$apptainer_url" > "$error_log" 2>&1; then
        echo "[$index/$total] ✓ Downloaded: $container_name"
        rm -f "$error_log"
        return 0
    else
        echo "[$index/$total] ✗ Failed: $container_name"
        # Show error details only on failure
        cat "$error_log" >&2
        rm -f "$error_log"
        return 1
    fi
}

export -f download_container

# Create a temporary file with container list
CONTAINER_LIST=$(mktemp)
echo "$CONTAINERS" > "$CONTAINER_LIST"

# Download containers in parallel using GNU parallel or xargs
TOTAL_CONTAINERS=$(cat "$CONTAINER_LIST" | grep -v "^$" | wc -l)
DOWNLOAD_FAILED=0

if command -v parallel &> /dev/null; then
    # Use GNU parallel if available
    cat "$CONTAINER_LIST" | grep -v "^$" | nl | parallel -j "$PARALLEL_DOWNLOADS" --will-cite --colsep '\t' \
        download_container {2} "$CONTAINER_DIR" {1} "$TOTAL_CONTAINERS" || DOWNLOAD_FAILED=1
else
    # Fall back to sequential download with background processes
    echo "Note: GNU parallel not found, using fallback parallel download method"
    index=0
    pids=()

    while IFS= read -r container; do
        [ -z "$container" ] && continue
        ((index++))

        # Wait if we've reached max parallel downloads
        while [ ${#pids[@]} -ge $PARALLEL_DOWNLOADS ]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                    wait "${pids[$i]}" || DOWNLOAD_FAILED=1
                    unset 'pids[i]'
                fi
            done
            pids=("${pids[@]}") # Reindex array
            sleep 0.5
        done

        # Start download in background
        download_container "$container" "$CONTAINER_DIR" "$index" "$TOTAL_CONTAINERS" &
        pids+=($!)
    done < "$CONTAINER_LIST"

    # Wait for remaining downloads
    for pid in "${pids[@]}"; do
        wait "$pid" || DOWNLOAD_FAILED=1
    done
fi

# Cleanup
rm -f "$INSPECT_JSON" "$CONTAINER_LIST"

echo ""
if [ $DOWNLOAD_FAILED -eq 0 ]; then
    echo -e "${GREEN}=== Download Complete ===${NC}"
    echo -e "${GREEN}✓ All containers downloaded successfully${NC}"
    echo "Container location: $CONTAINER_DIR"
    echo ""
    echo "To use these containers offline, set the following environment variables in your shell:"
    echo ""
    echo "export NXF_SINGULARITY_CACHEDIR='$CONTAINER_DIR'"
    echo "export NXF_APPTAINER_CACHEDIR='$CONTAINER_DIR'"
    echo "export SINGULARITY_CACHEDIR='$CONTAINER_DIR'"
    echo "export APPTAINER_CACHEDIR='$CONTAINER_DIR'"
    echo ""
    echo "You can then run your nextflow pipeline offline!"
    echo "Refer to the pipeline documentation for usage details."
    exit 0
else
    echo -e "${YELLOW}=== Download Complete with Warnings ===${NC}"
    echo -e "${YELLOW}⚠ Some containers failed to download${NC}"
    echo "Container location: $CONTAINER_DIR"
    echo "Cache location: $CACHE_DIR"
    exit 1
fi
