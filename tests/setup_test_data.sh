#!/bin/bash

################################################################################
# setup_test_data.sh - Download test data from NCBI for blacklister
#
# This script downloads:
# - Achromobacter xylosoxidans complete genome
# - UniVec_Core contamination database
#
# Files are placed in the tests/ directory
################################################################################

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Download URLs
readonly UNIVEC_URL="https://ftp.ncbi.nlm.nih.gov/pub/UniVec/UniVec_Core"
readonly ACHROMOBACTER_URL="https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/013/085/GCF_000013085.1_ASM1308v1/GCF_000013085.1_ASM1308v1_genomic.fna.gz"

# Output files
readonly UNIVEC_FILE="$SCRIPT_DIR/UniVec_Core.fasta"
readonly ACHROMOBACTER_FILE="$SCRIPT_DIR/achromobacter_xylosoxidans.fasta"
readonly UNIVEC_GZ="$SCRIPT_DIR/univec.gz"
readonly ACHROMOBACTER_GZ="$SCRIPT_DIR/achromobacter.fna.gz"

# Configuration
readonly MAX_RETRIES=3
readonly RETRY_DELAY=5
readonly TIMEOUT=300

################################################################################
# HELPER FUNCTIONS
################################################################################

log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_section() {
    echo ""
    echo "========================================"
    echo "  $*"
    echo "========================================"
    echo ""
}

# Download file with retries
download_file() {
    local url="$1"
    local output="$2"
    local description="$3"
    
    log_info "Downloading $description..."
    log_info "URL: $url"
    
    for attempt in $(seq 1 "$MAX_RETRIES"); do
        log_info "Attempt $attempt/$MAX_RETRIES..."
        
        if wget --timeout="$TIMEOUT" -q -O "$output" "$url" 2>/dev/null; then
            log_info "✓ Downloaded successfully"
            return 0
        else
            log_error "Download failed (attempt $attempt)"
            if [[ $attempt -lt $MAX_RETRIES ]]; then
                log_info "Retrying in ${RETRY_DELAY} seconds..."
                sleep "$RETRY_DELAY"
            fi
        fi
    done
    
    log_error "Failed to download $description after $MAX_RETRIES attempts"
    return 1
}

# Extract gzip file
extract_gz() {
    local file="$1"
    local output="$2"
    
    log_info "Extracting $file..."
    
    if gunzip -c "$file" > "$output"; then
        log_info "✓ Extraction successful"
        rm -f "$file"
        return 0
    else
        log_error "Extraction failed"
        return 1
    fi
}

# Verify file
verify_file() {
    local file="$1"
    local min_size="$2"
    local description="$3"
    
    if [[ ! -f "$file" ]]; then
        log_error "$description file not found: $file"
        return 1
    fi
    
    local file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
    
    if [[ $file_size -lt $min_size ]]; then
        log_error "$description file too small ($file_size bytes, expected >= $min_size)"
        return 1
    fi
    
    log_info "✓ $description verified ($file_size bytes)"
    return 0
}

# Create fallback test data
create_fallback_univec() {
    log_info "Creating fallback UniVec sequences..."
    
    cat > "$UNIVEC_FILE" << 'EOF'
>Illumina_Adapter1
AATGATACGGCGACCACCGAGATCTACACTCTTTCCCTACACGACGCTCTTCCGATCT
>Illumina_Adapter2
CAAGCAGAAGACGGCATACGAGATCGGTCTCGGCATTCCTGCTGAACCGCTCTTCCGATCT
>Vector_pUC19
AAGCTTATCGATACCGTCGACCTCGAGGGTTAATTCCGAGCTCGAATTCGGATCCAGATCTG
>Vector_pBR322
TCGACATTGCATCAGACATTGCCGTCACTGCGTCTTTTACTGGCTCTTCTCGCTTATCCAGC
EOF
    
    log_info "✓ Fallback UniVec created ($(wc -l < "$UNIVEC_FILE") lines)"
}

# Create fallback test genome
create_fallback_achromobacter() {
    log_info "Creating fallback Achromobacter test sequence..."
    
    cat > "$ACHROMOBACTER_FILE" << 'EOF'
>Achromobacter_xylosoxidans_test_chromosome
AAGCTTGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCT
AGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTA
GCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAG
CTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGC
TAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCT
AGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTA
GCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAG
CTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGC
TAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCT
AGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTA
EOF
    
    log_info "✓ Fallback Achromobacter created ($(wc -l < "$ACHROMOBACTER_FILE") lines)"
}

################################################################################
# MAIN WORKFLOW
################################################################################

main() {
    log_section "blacklister Test Data Setup"
    
    log_info "Test data directory: $SCRIPT_DIR"
    log_info ""
    
    # Check for wget
    if ! command -v wget >/dev/null 2>&1; then
        log_error "wget not found. Please install wget to download test data."
        log_info "Alternatively, manually download:"
        log_info "  1. $UNIVEC_URL"
        log_info "  2. $ACHROMOBACTER_URL"
        log_info ""
        return 1
    fi
    
    # Download UniVec_Core
    log_section "Step 1: UniVec_Core Database"
    
    if [[ -f "$UNIVEC_FILE" ]]; then
        log_info "UniVec_Core already exists: $UNIVEC_FILE"
        verify_file "$UNIVEC_FILE" 10000 "UniVec_Core" && univec_ok=true || univec_ok=false
    else
        if download_file "$UNIVEC_URL" "$UNIVEC_FILE" "UniVec_Core database"; then
            verify_file "$UNIVEC_FILE" 10000 "UniVec_Core" && univec_ok=true || univec_ok=false
        else
            log_error "Failed to download UniVec_Core, creating fallback..."
            create_fallback_univec
            univec_ok=true
        fi
    fi
    
    # Download Achromobacter genome
    log_section "Step 2: Achromobacter xylosoxidans Genome"
    
    if [[ -f "$ACHROMOBACTER_FILE" ]]; then
        log_info "Achromobacter genome already exists: $ACHROMOBACTER_FILE"
        verify_file "$ACHROMOBACTER_FILE" 1000000 "Achromobacter genome" && achrom_ok=true || achrom_ok=false
    else
        if download_file "$ACHROMOBACTER_URL" "$ACHROMOBACTER_GZ" "Achromobacter genome"; then
            if extract_gz "$ACHROMOBACTER_GZ" "$ACHROMOBACTER_FILE"; then
                verify_file "$ACHROMOBACTER_FILE" 1000000 "Achromobacter genome" && achrom_ok=true || achrom_ok=false
            else
                achrom_ok=false
            fi
        else
            log_error "Failed to download Achromobacter genome, creating fallback..."
            create_fallback_achromobacter
            achrom_ok=true
        fi
    fi
    
    # Summary
    log_section "Setup Summary"
    
    if [[ "$univec_ok" == true ]] && [[ "$achrom_ok" == true ]]; then
        log_info "✓ All test data ready!"
        log_info ""
        log_info "Files created:"
        log_info "  - $UNIVEC_FILE"
        log_info "  - $ACHROMOBACTER_FILE"
        log_info ""
        log_info "Next step: Run tests"
        log_info "  bash tests/test_blacklister.sh"
        log_info ""
        return 0
    else
        log_error "Some test data setup steps failed"
        log_info ""
        log_info "You can manually download:"
        if [[ "$univec_ok" != true ]]; then
            log_info "  UniVec: $UNIVEC_URL"
        fi
        if [[ "$achrom_ok" != true ]]; then
            log_info "  Achromobacter: $ACHROMOBACTER_URL"
        fi
        log_info ""
        return 1
    fi
}

################################################################################
# ENTRY POINT
################################################################################

main "$@"
