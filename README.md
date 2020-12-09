# blacklister
 * Blacklist (mask with N) regions in a metagenome (multi-FASTA file) to which a user-supplied fasta file (adapters) were aligned 
 * Eg Mask Illumina adapters in bad bacterial genomes (Achromobacter is fun!).
 * Very simple alternative to RepeatMasker without the complexity (and features)


Process:
  * bowtie2 with --all parameter shows all alignments much better than bwa mem. Use bowtie2.
  * bedtools does the conversion BAM to bed
  * bedtools fasta masking using the bed


See blacklister.sh for examples and a workflow. 

## Installation
  Requires only following tools in PATH
  * bowtie2 (tested with v2.3.4.3)
  * bedtools (v2.26 tested)
  * bbmap (for readlength.sh stats output)
  


## How to run

```
  # First change input file, reference and number of threads used in script. 
  # Reference FASTA needs a bowtie2 index, build if needed (takes 5+hours for big genomes)
  # Now run directly:
  bash blacklister.sh
  # Or run via SLURM scheduler if available
  srun -c 12 bash blacklister.sh
```
## Input
* Fasta file of reference sequences to be masked (reference genome or metagenome)
* Fasta file of contaminant sequences to be masked (with Ns) in the reference genome (if and where these contaminants align)

## Output
* SAM file of alignment (usual small as input, eg, adapter fasta file or UniVec DB, are quite small)
* BAM file of alignment (temporary, converted to BED to be used for masking)
* BED file of alignment (used for bedtools maskfasta)
* N-masked multi-fasta file. Filename: input.fa.masked.fa. Created in the same location as the input reference file to be masked, not in the local directory.
* Statistics (on standard out). Number of masked lines in reference (containing 3 Ns or more) before and after masking. Also number of chromosomes input and output (via bbmap readlength.sh)




## Notes:

```
  ### masking commands to extract and check masked genomes
  samtools faidx 2sp_univec.fa.masked.fa 1_CP015639_1_Pseudomonas_lurida_strain_L228_chromosome__complete_genome_BAC > lu_masked.fa
  samtools faidx 2sp_univec.fa.masked.fa 1_CP006958_1_UNVERIFIED__Achromobacter_xylosoxidans_NBRC_15126___ATCC_27061__complete_genome_BAC > achrom_masked.fa

  grep NNN lu_masked.fa
  grep NNN achrom_masked.fa
```
