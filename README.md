# blacklister

A simple tool to mask (replace with N) regions in genomic or metagenomic sequences where contaminant sequences (e.g., Illumina adapters, vector contamination) align.

**Use case:** Clean up metagenomic reference sequences or genome assemblies by masking adapter sequences, UniVec contamination, or other known problematic sequences.

**Example:** Mask Illumina adapters in bacterial genomes (e.g., Achromobacter) that may interfere with downstream analyses.

**Why blacklister?** A much simpler alternative to RepeatMasker without the added complexity and features—ideal for targeted contamination masking.

**Author:** Colin Davenport, Hannover Medical School

**Current Version:** 0.14

---

## Overview

### Process
The blacklister workflow consists of three key steps:

1. **Alignment** - Use bowtie2 with `--all` parameter to find all alignments of contaminant sequences against your reference
   - `bowtie2` is preferred over `bwa mem` for comprehensive alignment detection
2. **Format Conversion** - Convert BAM alignment file to BED format
   - Uses `bedtools` for efficient format conversion
3. **Masking** - Replace aligned regions with N bases using BED coordinates
   - Uses `bedtools maskfasta` to perform the actual sequence masking

---

## Installation

### Requirements
The following tools must be in your system PATH:

* **bowtie2** (tested with v2.3.4.3)
* **bedtools** (tested with v2.26)
* **samtools** (for BAM/SAM processing)
* **bbmap** (optional, for readlength.sh statistics output)

### Verify Installation
```bash
bowtie2 --version
bedtools --version
samtools --version
```

---

## Quick Start

### 1. Build a bowtie2 index for your reference (one-time setup)
```bash
# This takes 5+ hours for large genomes (>1GB)
bowtie2-build -f my_reference.fa my_reference.fa
```

### 2. Prepare your contaminant sequences
Create a FASTA file containing sequences to mask. Common options:
- `UniVec_Core.fasta` (adapter and vector sequences)
- Custom adapter sequences
- Known contamination sequences

### 3. Run blacklister

#### Option A: Command-line argument (recommended for v0.14+)
```bash
bash blacklister.sh /path/to/my_reference.fa
```

#### Option B: Edit the script
Edit `blacklister.sh` and modify these variables in the "Users: Modify this section":
```bash
thr=24                                           # Number of threads
ref=/path/to/my_reference.fa                     # Reference FASTA (with bowtie2 index)
input=/path/to/contaminants.fa                   # Contamination sequences to mask
```
Then run:
```bash
bash blacklister.sh
```

#### Option C: Submit to SLURM scheduler
```bash
srun -c 24 bash blacklister.sh /path/to/my_reference.fa
```

---

## Configuration

### Variables in blacklister.sh

| Variable | Description | Example |
|----------|-------------|---------|
| `thr` | Number of threads for bowtie2 | `24` |
| `ref` | Path to reference FASTA file (must have bowtie2 index) | `/path/to/genome.fa` |
| `input` | Path to contaminant/adapter FASTA sequences | `/path/to/UniVec_Core.fasta` |

### Examples of Reference Files
The script includes commented examples:
```bash
#ref=/lager2/rcug/seqres/metagenref/bowtie2/refSeqs_allKingdoms_2020_03.fa
#ref=/lager2/rcug/seqres/metagenref/bowtie2/Virus_Fungi3.fasta
#ref=/lager2/rcug/seqres/metagenref/bowtie2/mm10_plus_ASF.fasta
```

---

## Input

* **Reference FASTA** - The genome/metagenome to be masked (contaminant regions will be masked with Ns)
* **Contaminant FASTA** - Adapter sequences, vector sequences, or other known contamination (sequences to find and mask in the reference)
  - Must be in FASTA format
  - Typically much smaller than reference (e.g., UniVec_Core is ~50 KB)

**Important:** The reference FASTA must have a prebuilt bowtie2 index:
```bash
bowtie2-build -f reference.fa reference.fa
```

---

## Output

The tool generates several output files:

| File | Description |
|------|-------------|
| `bt.test.s.bam` | Aligned sequences in BAM format (intermediate) |
| `bt.test.s.bam.txt` | BAM index statistics (intermediate) |
| `bt.test.s.bam.bed` | BED format of alignments (intermediate, used for masking) |
| `input.fa.masked.fa` | **Final output** - Reference FASTA with N-masked contamination regions |
| `bt.test.s.bam.readlength` | Sequence statistics (if bbmap available) |

### Important Output Location
⚠️ **The masked FASTA output is created in the SAME DIRECTORY as the reference file and bowtie2 index**, NOT in the local working directory.

**Example:**
```
If reference is at: /data/genomes/my_reference.fa
Masked output goes to: /data/genomes/my_reference.fa.masked.fa
```

### Statistics Output
Standard output shows:
- Number of masked lines (containing 3+ Ns) before and after masking
- Number of input/output chromosomes or sequences
- Summary of masking statistics

---

## Extracting Specific Masked Sequences

After masking, extract individual sequences from the masked FASTA using samtools:

```bash
# Extract a single masked chromosome
samtools faidx reference.fa.masked.fa chromosome_name > output.fa

# Example with UniVec masking
samtools faidx genome_univec.fa.masked.fa Pseudomonas_lurida_chromosome > lu_masked.fa

# Check for masked regions (Ns)
grep NNN lu_masked.fa
```

---

## Technical Details

### Why bowtie2 instead of bwa?

The `--all` parameter in bowtie2 reports **all alignments** including:
- Partial matches
- Multiple mapping locations
- Weak alignments

This is critical for contamination detection where you want to find **every instance** of adapter sequences, not just the best match. `bwa mem` is optimized for best-match reporting and misses secondary alignments.

### Workflow Commands

The script executes the following pipeline:

```bash
# Step 1: Align contaminants to reference, convert to BAM
bowtie2 -p $thr --all -f -x $ref -U $input | samtools view -@ 8 -bhS - | samtools sort - > bt.test.s.bam

# Step 2: Index BAM and generate statistics
samtools index bt.test.s.bam
samtools idxstats bt.test.s.bam > bt.test.s.bam.txt

# Step 3: Convert BAM to BED for masking
bedtools bamtobed -i bt.test.s.bam > bt.test.s.bam.bed

# Step 4: Mask contaminated regions with Ns
bedtools maskfasta -fi $ref -bed bt.test.s.bam.bed -fo $ref.masked.fa
```

---

## Troubleshooting

### Index Building Takes Too Long
- Bowtie2 index building is **I/O intensive** and can take 5+ hours for large genomes (>1GB)
- Run on a fast filesystem (not network-mounted storage if possible)
- Use more threads if available to parallelize: `bowtie2-build -p 24 -f reference.fa reference.fa`

### "bowtie2-index: command not found"
- Ensure bowtie2 is installed and in your PATH
- Verify: `bowtie2 --version`

### "Tool not found" Errors
- Check that samtools, bedtools, and bowtie2 are installed
- Add to PATH if needed: `export PATH=/path/to/tool/bin:$PATH`

### No Alignments Found (Empty Output)
- Verify contaminant sequences are actually present in reference
- Check bowtie2 index is in the same directory as reference FASTA
- Ensure FASTA files are valid (not corrupted)

### Output File Not Found
- Check the reference file directory, not the working directory
- Example: If ref is `/data/ref.fa`, look for `/data/ref.fa.masked.fa`

---

## Changelog

- **v0.14** - Improve docs, add ref as command-line argument
- **v0.13** - Update reference sequence locations and documentation
- **v0.12** - Expand docs and formatting
- **v0.11** - Add bowtie2 index for refSeqs_allKingdoms_201910_3.fasta
- **v0.10** - Initial commits

---

## Notes

### Example Masking Commands
Extract and verify masked sequences:

```bash
# Extract specific chromosomes after masking
samtools faidx genome_univec.fa.masked.fa "1_CP015639_1_Pseudomonas_lurida_strain_L228_chromosome__complete_genome_BAC" > lu_masked.fa
samtools faidx genome_univec.fa.masked.fa "1_CP006958_1_UNVERIFIED__Achromobacter_xylosoxidans_NBRC_15126___ATCC_27061__complete_genome_BAC" > achrom_masked.fa

# Verify masking worked (find 3+ consecutive Ns)
grep NNN lu_masked.fa
grep NNN achrom_masked.fa
```

---

## License & Attribution

**Author:** Colin Davenport, Hannover Medical School

For questions or issues, please open an issue on GitHub.
