#!/bin/bash

################################################################################
# blacklister.sh - Mask contamination sequences in reference genomes
# 
# Purpose: Identify and mask adapter/contaminant sequences in reference FASTA
#          using bowtie2 alignment and bedtools masking
#
# Author:  Colin Davenport, Hannover Medical School
# Updated: May 2026
################################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

################################################################################
# VERSION & CONFIGURATION
################################################################################

readonly SCRIPT_VERSION="0.15"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Output file prefixes
readonly OUTPUT_PREFIX="blacklister"
readonly BAM_FILE="${OUTPUT_PREFIX}.bam"
readonly BAM_INDEX="${OUTPUT_PREFIX}.bam.bai"
readonly SAM_FILE="${OUTPUT_PREFIX}.sam"
readonly BED_FILE="${OUTPUT_PREFIX}.bed"
readonly STATS_FILE="${OUTPUT_PREFIX}.stats.txt"

################################################################################
# USER CONFIGURATION - MODIFY THIS SECTION
################################################################################

# Number of threads for bowtie2
THREADS=24

# Reference FASTA file (must have bowtie2 index)
# Can be supplied as first command-line argument
REFERENCE_FASTA="${1:-}"

# Input FASTA file with contaminant sequences to mask
# Examples: adapters, UniVec_Core.fasta, vector sequences
CONTAMINANT_FASTA="/mnt/ngsnfs/seqres/contaminants/2020_02/univec/UniVec_Core.fasta"

################################################################################
# HELPER FUNCTIONS
################################################################################

# Print colored output messages
log_info() {
    echo "[INFO $(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_error() {
    echo "[ERROR $(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

log_warn() {
    echo "[WARN $(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_section() {
    echo ""
    echo "================================================================================"
    echo "  $*"
    echo "================================================================================"
    echo ""
}

# Check if command exists in PATH
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if file exists and is readable
file_exists() {
    [[ -f "$1" && -r "$1" ]]
}

# Validate dependencies
check_dependencies() {
    local missing_tools=()
    
    for tool in bowtie2 samtools bedtools; do
        if ! command_exists "$tool"; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install the following tools and add them to PATH:"
        log_error "  - bowtie2 (v2.3.4.3+)"
        log_error "  - samtools (v1.10+)"
        log_error "  - bedtools (v2.26+)"
        return 1
    fi
    
    log_info "All required dependencies found ✓"
}

# Validate input files
validate_inputs() {
    # Check reference file
    if [[ -z "$REFERENCE_FASTA" ]]; then
        log_error "Reference FASTA not specified!"
        log_error "Usage: $SCRIPT_NAME <reference.fa>"
        log_error "Or edit the script and set REFERENCE_FASTA variable"
        return 1
    fi
    
    if ! file_exists "$REFERENCE_FASTA"; then
        log_error "Reference FASTA file not found: $REFERENCE_FASTA"
        return 1
    fi
    
    # Check bowtie2 index
    local index_base=$(echo "$REFERENCE_FASTA" | sed 's/\.[^.]*$//')
    if ! file_exists "${index_base}.1.bt2"; then
        log_error "bowtie2 index not found for: $REFERENCE_FASTA"
        log_error "Build the index with: bowtie2-build -f $REFERENCE_FASTA $index_base"
        return 1
    fi
    
    # Check contaminant file
    if ! file_exists "$CONTAMINANT_FASTA"; then
        log_error "Contaminant FASTA file not found: $CONTAMINANT_FASTA"
        return 1
    fi
    
    log_info "All input files validated ✓"
}

# Get sequence count from FASTA file
count_sequences() {
    grep -c "^>" "$1" 2>/dev/null || echo "0"
}

# Get total bases from FASTA file
count_bases() {
    awk '/^>/ {next} {sum += length} END {print sum}' "$1" 2>/dev/null || echo "0"
}

# Count lines with N stretches
count_n_stretches() {
    local pattern="${1:-NNN}"
    local file="$2"
    grep -c "$pattern" "$file" 2>/dev/null || echo "0"
}

# Print summary statistics
print_statistics() {
    local ref_file="$1"
    local masked_file="$2"
    
    log_section "MASKING STATISTICS"
    
    # Input statistics
    log_info "Reference file: $(basename "$ref_file")"
    log_info "  Sequences: $(count_sequences "$ref_file")"
    log_info "  Total bases: $(count_bases "$ref_file")"
    
    log_info ""
    log_info "Contaminant file: $(basename "$CONTAMINANT_FASTA")"
    log_info "  Sequences: $(count_sequences "$CONTAMINANT_FASTA")"
    log_info "  Total bases: $(count_bases "$CONTAMINANT_FASTA")"
    
    # Alignment statistics
    if [[ -f "$BED_FILE" ]]; then
        local alignment_count=$(wc -l < "$BED_FILE")
        log_info ""
        log_info "Alignment statistics:"
        log_info "  Total aligned regions (BED entries): $alignment_count"
        
        if [[ -f "$BED_FILE" ]]; then
            local total_masked_bp=$(awk '{sum += ($3 - $2)} END {print sum}' "$BED_FILE")
            log_info "  Total bases masked: $total_masked_bp"
            local ref_bases=$(count_bases "$ref_file")
            if [[ $ref_bases -gt 0 ]]; then
                local pct=$((total_masked_bp * 100 / ref_bases))
                log_info "  Percentage masked: ${pct}%"
            fi
        fi
    fi
    
    # N content before/after
    local nnn_before=$(count_n_stretches "NNN" "$ref_file")
    local nnn_after=$(count_n_stretches "NNN" "$masked_file")
    
    log_info ""
    log_info "N-stretch statistics (3+ consecutive Ns):"
    log_info "  Before masking: $nnn_before lines"
    log_info "  After masking:  $nnn_after lines"
    log_info "  New N-stretches added: $((nnn_after - nnn_before))"
    
    # SAM/BAM statistics
    if [[ -f "$SAM_FILE" ]]; then
        local sam_lines=$(grep -v "^@" "$SAM_FILE" 2>/dev/null | wc -l || echo "0")
        log_info ""
        log_info "SAM alignment records: $sam_lines"
    fi
    
    log_info ""
}

# Print detailed file information
print_file_summary() {
    log_section "OUTPUT FILES GENERATED"
    
    local file_list=(
        "BAM (indexed):$BAM_FILE"
        "SAM (text):$SAM_FILE"
        "BED (masking regions):$BED_FILE"
        "Statistics:$STATS_FILE"
    )
    
    for entry in "${file_list[@]}"; do
        IFS=':' read -r desc file <<< "$entry"
        if [[ -f "$file" ]]; then
            local size=$(du -h "$file" | cut -f1)
            echo "  ✓ $desc ($size)"
        else
            echo "  ✗ $file (not found)"
        fi
    done
    
    # Final output
    local masked_output="${REFERENCE_FASTA}.masked.fa"
    if [[ -f "$masked_output" ]]; then
        local size=$(du -h "$masked_output" | cut -f1)
        echo "  ✓ MASKED REFERENCE: $masked_output ($size)"
    fi
    echo ""
}

################################################################################
# MAIN WORKFLOW
################################################################################

main() {
    local start_time=$(date +%s)
    
    log_section "blacklister v${SCRIPT_VERSION} - Contamination Masking Tool"
    
    log_info "Starting blacklister workflow"
    log_info "Threads: $THREADS"
    log_info "Reference: $REFERENCE_FASTA"
    log_info "Contaminants: $CONTAMINANT_FASTA"
    log_info ""
    
    # Validate environment
    check_dependencies || exit 1
    validate_inputs || exit 1
    
    # Determine reference directory for output
    local ref_dir=$(dirname "$(cd "$(dirname "$REFERENCE_FASTA")" && pwd -P)/$(basename "$REFERENCE_FASTA")")
    local ref_base=$(basename "$REFERENCE_FASTA")
    log_info "Output directory: $ref_dir"
    log_info ""
    
    # STEP 1: Alignment with bowtie2
    log_section "STEP 1: Aligning contaminants to reference"
    log_info "Command: bowtie2 -p $THREADS --all -f -x $REFERENCE_FASTA -U $CONTAMINANT_FASTA"
    
    if bowtie2 -p "$THREADS" --all -f -x "$REFERENCE_FASTA" -U "$CONTAMINANT_FASTA" 2>/dev/null \
        | samtools view -@ 8 -bhS - 2>/dev/null \
        | samtools sort - 2>/dev/null > "$BAM_FILE"; then
        log_info "Alignment completed successfully ✓"
    else
        log_error "Alignment failed!"
        return 1
    fi
    
    # Index BAM file
    log_info "Indexing BAM file..."
    if samtools index "$BAM_FILE" 2>/dev/null; then
        log_info "BAM indexing completed ✓"
    else
        log_error "BAM indexing failed!"
        return 1
    fi
    
    # Generate statistics
    log_info "Generating BAM statistics..."
    samtools idxstats "$BAM_FILE" > "${OUTPUT_PREFIX}.idxstats" 2>/dev/null
    
    # Export to SAM for inspection
    log_info "Exporting to SAM format..."
    samtools view -h "$BAM_FILE" > "$SAM_FILE" 2>/dev/null
    log_info ""
    
    # STEP 2: Convert BAM to BED
    log_section "STEP 2: Converting alignment to BED format"
    log_info "Command: bedtools bamtobed -i $BAM_FILE"
    
    if bedtools bamtobed -ed -i "$BAM_FILE" > "$BED_FILE" 2>/dev/null; then
        local bed_regions=$(wc -l < "$BED_FILE")
        log_info "BED conversion completed ✓"
        log_info "Alignment regions: $bed_regions"
    else
        log_error "BED conversion failed!"
        return 1
    fi
    log_info ""
    
    # STEP 3: Mask FASTA
    log_section "STEP 3: Masking contaminated regions"
    local masked_output="${REFERENCE_FASTA}.masked.fa"
    log_info "Output file: $masked_output"
    log_info "Command: bedtools maskfasta -fi $REFERENCE_FASTA -bed $BED_FILE"
    
    if bedtools maskfasta -fi "$REFERENCE_FASTA" -bed "$BED_FILE" -fo "$masked_output" 2>/dev/null; then
        log_info "Masking completed successfully ✓"
    else
        log_error "Masking failed!"
        return 1
    fi
    log_info ""
    
    # Print statistics and summaries
    print_statistics "$REFERENCE_FASTA" "$masked_output"
    print_file_summary
    
    # Timing
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    log_section "COMPLETION"
    log_info "✓ blacklister workflow completed successfully!"
    log_info "Execution time: ${minutes}m ${seconds}s"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Verify masking: grep NNN $masked_output | head"
    log_info "  2. Extract sequences: samtools faidx $masked_output <sequence_name>"
    log_info "  3. Check alignment regions: head $BED_FILE"
    log_info ""
}

################################################################################
# ENTRY POINT
################################################################################

main "$@"
