#!/bin/bash

################################################################################
# test_blacklister.sh - Comprehensive test suite for blacklister
#
# Tests include:
# - Input validation
# - Full workflow execution
# - Output file validation
# - Output content correctness
# - Masking effectiveness
# - Post-processing commands
################################################################################

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly TEST_DIR="$SCRIPT_DIR"
readonly WORK_DIR="$TEST_DIR/work"

# Test data files
readonly UNIVEC_FILE="$TEST_DIR/UniVec_Core.fasta"
readonly ACHROMOBACTER_FILE="$TEST_DIR/achromobacter_xylosoxidans.fasta"
readonly REFERENCE_TEST="$WORK_DIR/reference_test.fa"
readonly MASKED_OUTPUT="$WORK_DIR/reference_test.fa.masked.fa"

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

################################################################################
# HELPER FUNCTIONS
################################################################################

log_info() {
    echo "[INFO] $*"
}

log_section() {
    echo ""
    echo "=================================================="
    echo "  $*"
    echo "=================================================="
    echo ""
}

log_test() {
    echo "[TEST] $*"
}

log_success() {
    echo "[TEST] ✓ $*"
}

log_fail() {
    echo "[TEST] ✗ $*"
}

# Assert file exists
assert_file_exists() {
    local file="$1"
    local description="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ -f "$file" ]]; then
        log_success "$description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_fail "$description (not found: $file)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Assert file contains pattern
assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local description="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if grep -q "$pattern" "$file" 2>/dev/null; then
        log_success "$description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_fail "$description (pattern not found: $pattern)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Assert file has minimum lines
assert_file_min_lines() {
    local file="$1"
    local min_lines="$2"
    local description="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    local line_count=$(wc -l < "$file" || echo "0")
    
    if [[ $line_count -ge $min_lines ]]; then
        log_success "$description ($line_count lines)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_fail "$description (expected >= $min_lines, got $line_count)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Assert command succeeds
assert_command_succeeds() {
    local description="$1"
    shift
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if "$@" >/dev/null 2>&1; then
        log_success "$description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_fail "$description"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get sequence length
get_fasta_length() {
    local file="$1"
    awk '/^>/ {next} {sum += length} END {print sum}' "$file" 2>/dev/null || echo "0"
}

################################################################################
# TEST SUITES
################################################################################

test_input_validation() {
    log_section "TEST SUITE 1: Input File Validation"
    
    assert_file_exists "$UNIVEC_FILE" "UniVec_Core database exists"
    assert_file_exists "$ACHROMOBACTER_FILE" "Reference genome exists"
    assert_file_contains "$UNIVEC_FILE" "^>" "UniVec contains sequences"
    assert_file_contains "$ACHROMOBACTER_FILE" "^>" "Reference contains sequences"
}

test_dependencies() {
    log_section "TEST SUITE 2: Dependency Checking"
    
    assert_command_succeeds "bowtie2 is available" command_exists bowtie2
    assert_command_succeeds "samtools is available" command_exists samtools
    assert_command_succeeds "bedtools is available" command_exists bedtools
}

test_index_building() {
    log_section "TEST SUITE 3: bowtie2 Index Building"
    
    log_info "Building bowtie2 index (this may take several minutes)..."
    
    # Check if index exists
    local index_base=$(echo "$REFERENCE_TEST" | sed 's/\.[^.]*$//')
    
    if [[ ! -f "${index_base}.1.bt2" ]]; then
        log_info "Index not found, building..."
        if bowtie2-build -f "$REFERENCE_TEST" "$index_base" >/dev/null 2>&1; then
            log_success "bowtie2 index built successfully"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            TESTS_RUN=$((TESTS_RUN + 1))
        else
            log_fail "bowtie2 index build failed"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            TESTS_RUN=$((TESTS_RUN + 1))
            return 1
        fi
    else
        log_success "bowtie2 index exists"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        TESTS_RUN=$((TESTS_RUN + 1))
    fi
}

test_blacklister_execution() {
    log_section "TEST SUITE 4: blacklister Execution"
    
    log_info "Running blacklister workflow..."
    
    if bash "$PROJECT_DIR/blacklister.sh" "$REFERENCE_TEST" >/dev/null 2>&1; then
        log_success "blacklister executed without errors"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        TESTS_RUN=$((TESTS_RUN + 1))
    else
        log_fail "blacklister execution failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        TESTS_RUN=$((TESTS_RUN + 1))
        return 1
    fi
}

test_output_files() {
    log_section "TEST SUITE 5: Output File Validation"
    
    assert_file_exists "$WORK_DIR/blacklister.bam" "BAM alignment file exists"
    assert_file_exists "$WORK_DIR/blacklister.sam" "SAM alignment file exists"
    assert_file_exists "$WORK_DIR/blacklister.bed" "BED regions file exists"
    assert_file_exists "$MASKED_OUTPUT" "Masked FASTA output exists"
    
    # Check file sizes
    TESTS_RUN=$((TESTS_RUN + 1))
    local bam_size=$(stat -f%z "$WORK_DIR/blacklister.bam" 2>/dev/null || stat -c%s "$WORK_DIR/blacklister.bam" 2>/dev/null || echo "0")
    if [[ $bam_size -gt 100 ]]; then
        log_success "BAM file has reasonable size ($bam_size bytes)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "BAM file too small ($bam_size bytes)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

test_output_content() {
    log_section "TEST SUITE 6: Output Content Validation"
    
    assert_file_contains "$WORK_DIR/blacklister.sam" "^@" "SAM file has headers"
    assert_file_contains "$WORK_DIR/blacklister.bed" "[0-9]" "BED file has numeric data"
    assert_file_contains "$MASKED_OUTPUT" "^>" "Masked FASTA has sequences"
    assert_file_min_lines "$WORK_DIR/blacklister.bed" 1 "BED file has alignment regions"
}

test_masking_effect() {
    log_section "TEST SUITE 7: Masking Effect Validation"
    
    # Compare sequence lengths
    TESTS_RUN=$((TESTS_RUN + 1))
    local ref_length=$(get_fasta_length "$REFERENCE_TEST")
    local masked_length=$(get_fasta_length "$MASKED_OUTPUT")
    
    if [[ $ref_length -eq $masked_length ]]; then
        log_success "Sequence lengths match ($ref_length bp)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "Sequence lengths don't match (ref: $ref_length, masked: $masked_length)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    # Check if Ns were added
    TESTS_RUN=$((TESTS_RUN + 1))
    local masked_n_count=$(grep -o 'N' "$MASKED_OUTPUT" 2>/dev/null | wc -l || echo "0")
    if [[ $masked_n_count -gt 0 ]]; then
        log_success "N bases added during masking ($masked_n_count Ns)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "No N bases found in masked output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

test_postprocessing() {
    log_section "TEST SUITE 8: Post-Processing Commands"
    
    # Test samtools faidx
    if [[ -f "$MASKED_OUTPUT" ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        if samtools faidx "$MASKED_OUTPUT" >/dev/null 2>&1; then
            log_success "samtools faidx works on masked output"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            log_fail "samtools faidx failed"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    fi
    
    # Test grep for Ns
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q "^[ACGT]*N" "$MASKED_OUTPUT" 2>/dev/null; then
        log_success "Can find N-containing lines with grep"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "grep for N lines failed or no Ns found"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

################################################################################
# MAIN TEST RUNNER
################################################################################

main() {
    log_section "blacklister Test Suite"
    
    log_info "Project directory: $PROJECT_DIR"
    log_info "Test directory: $TEST_DIR"
    log_info "Work directory: $WORK_DIR"
    log_info ""
    
    # Check test data exists
    if [[ ! -f "$UNIVEC_FILE" ]] || [[ ! -f "$ACHROMOBACTER_FILE" ]]; then
        log_fail "Test data not found!"
        log_info "Please run: bash tests/setup_test_data.sh"
        return 1
    fi
    
    # Create work directory
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"
    
    # Copy reference to work directory
    cp "$ACHROMOBACTER_FILE" "$REFERENCE_TEST"
    
    # Copy bowtie2 index to work directory if it exists
    local orig_index_base=$(echo "$ACHROMOBACTER_FILE" | sed 's/\.[^.]*$//')
    local work_index_base=$(echo "$REFERENCE_TEST" | sed 's/\.[^.]*$//')
    
    for ext in 1.bt2 2.bt2 3.bt2 4.bt2 rev.1.bt2 rev.2.bt2; do
        if [[ -f "${orig_index_base}.${ext}" ]]; then
            cp "${orig_index_base}.${ext}" "${work_index_base}.${ext}"
        fi
    done
    
    log_info "Setup complete, starting tests..."
    log_info ""
    
    # Run test suites
    test_input_validation
    test_dependencies
    test_index_building || true
    test_blacklister_execution || true
    test_output_files
    test_output_content
    test_masking_effect
    test_postprocessing
    
    # Print summary
    log_section "Test Summary"
    
    echo "Tests run:    $TESTS_RUN"
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "All tests passed! ✓"
        log_info ""
        log_info "Next steps:"
        log_info "  - Check outputs in: $WORK_DIR"
        log_info "  - View masked sequences: head -20 $MASKED_OUTPUT"
        log_info "  - Clean up: rm -rf $WORK_DIR"
        log_info ""
        return 0
    else
        log_fail "$TESTS_FAILED test(s) failed!"
        log_info ""
        log_info "Debugging tips:"
        log_info "  - Check work directory: ls -la $WORK_DIR"
        log_info "  - Check for errors: grep -i error $WORK_DIR/*.log"
        log_info "  - Run blacklister manually: bash $PROJECT_DIR/blacklister.sh $REFERENCE_TEST"
        log_info ""
        return 1
    fi
}

################################################################################
# ENTRY POINT
################################################################################

main "$@"
