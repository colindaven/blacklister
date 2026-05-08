# Test Suite for blacklister

This directory contains test scripts and data for validating blacklister functionality.

## Quick Start

### 1. Download Test Data
```bash
bash tests/setup_test_data.sh
```

This will download:
- **UniVec_Core.fasta** - NCBI contamination database (~50 KB)
- **achromobacter_xylosoxidans.fasta** - Complete bacterial genome (~7 MB)

### 2. Run Tests
```bash
bash tests/test_blacklister.sh
```

The test script will:
1. Verify all prerequisites and test data
2. Build bowtie2 index (if needed)
3. Run the complete blacklister workflow
4. Validate all output files
5. Verify masking effects
6. Test post-processing commands

## Test Scripts

### `setup_test_data.sh`
Downloads and verifies test data from NCBI.

**Features:**
- Downloads Achromobacter genome from NCBI
- Downloads UniVec_Core contamination database
- Verifies file integrity
- Fallback to minimal test data if downloads fail
- Retry logic for network failures

**Usage:**
```bash
bash tests/setup_test_data.sh
```

### `test_blacklister.sh`
Comprehensive integration test suite with multiple test suites.

**Test Suites:**
1. **Input File Validation** - Verify test data exists and is valid
2. **blacklister Execution** - Run the full workflow
3. **Output File Validation** - Check all expected output files exist
4. **Output Content Validation** - Verify output file structure and content
5. **Masking Effect Validation** - Confirm N-bases were added correctly
6. **Post-processing Commands** - Test samtools and grep operations

**Usage:**
```bash
bash tests/test_blacklister.sh
```

## Test Data

### Files
- `achromobacter_xylosoxidans.fasta` - Reference genome
- `UniVec_Core.fasta` - Contamination sequences
- `work/` - Working directory for test execution (auto-created)

### Expected Content
- **Reference genome**: ~7 MB, complete bacterial chromosome
- **UniVec_Core**: ~50 KB, common adapter/vector sequences
- **Work directory**: Contains:
  - `reference_test.fa` - Copy of genome
  - `blacklister.bam` - Alignment file
  - `blacklister.sam` - SAM format alignments
  - `blacklister.bed` - BED format regions
  - `reference_test.fa.masked.fa` - Final masked output

## Requirements

### Tools
- **bash** (v4.0+)
- **bowtie2** (v2.3.4+)
- **samtools** (v1.10+)
- **bedtools** (v2.26+)
- **wget** (for downloading test data)

### Disk Space
- ~50 MB for test data and output (original files)
- ~500 MB for bowtie2 index (depends on genome size)

### Time
- First run: ~10-15 minutes (includes index building)
- Subsequent runs: ~1-2 minutes (index reused)

## Example Output

```
[INFO] ==================================================
[INFO] blacklister Test Suite
[INFO] ==================================================
[INFO] Project directory: /path/to/blacklister
[INFO] Test data directory: /path/to/blacklister/tests

[TEST] ✓ Reference genome exists
[TEST] ✓ Contaminant database exists
[TEST] ✓ blacklister executed without errors
[TEST] ✓ BAM alignment file exists
[TEST] ✓ SAM alignment file exists
[TEST] ✓ Masked FASTA output exists
[TEST] ✓ Sequence lengths match (8234 bp)

[INFO] ==================================================
[INFO] Test Summary
[INFO] ==================================================
Tests run:    24
Tests passed: 24
Tests failed: 0

[INFO] All tests passed! ✓
```

## Troubleshooting

### Network Download Fails
- The script retries 3 times automatically
- Check internet connection
- Verify NCBI FTP is accessible: `wget https://ftp.ncbi.nlm.nih.gov/pub/UniVec/UniVec_Core -O /tmp/test_ncbi`

### bowtie2 Index Building Fails
- Ensure bowtie2 is installed: `bowtie2 --version`
- Check disk space: `df -h`
- Try building manually: `bowtie2-build -f tests/achromobacter_xylosoxidans.fasta tests/achromobacter_xylosoxidans.fasta`

### Tests Fail with "tool not found"
- Install missing tools: samtools, bedtools, bowtie2
- Add to PATH: `export PATH=/path/to/tool/bin:$PATH`

### Missing Test Data
- Run `bash tests/setup_test_data.sh` again
- Check network connectivity
- Verify write permissions in tests directory: `ls -la tests/`

## Integration with CI/CD

The test suite can be integrated into CI/CD pipelines:

```bash
#!/bin/bash
set -e

# Setup test data
bash tests/setup_test_data.sh

# Run tests
bash tests/test_blacklister.sh

# Clean up
rm -rf tests/work tests/*.1.bt2 tests/*.2.bt2 tests/*.3.bt2 tests/*.4.bt2 tests/*.rev.1.bt2 tests/*.rev.2.bt2
```

## Adding New Tests

To add new tests, modify `test_blacklister.sh`:

```bash
test_new_feature() {
    log_section "TEST SUITE N: New Feature"
    
    # Your test code here
    assert_file_exists "output.txt" "Expected output file"
    assert_command_succeeds "Run my command" my_command arg1 arg2
}

# Add to main() function
```

Available assertions:
- `assert_file_exists <file> <description>`
- `assert_file_contains <file> <pattern> <description>`
- `assert_file_min_lines <file> <count> <description>`
- `assert_command_succeeds <description> <command>`

## License

These test scripts are part of blacklister and use the same license as the main project.
