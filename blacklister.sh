#!/bin/bash
# Colin Davenport, May 2020
# BlackLister script: masks dodgy sequences such as adapters in reference multifasta sequences like metagenomes
# First change input file, reference and number of threads used in script. 
# Reference FASTA needs a bowtie2 index, build if needed (takes 5+hours for big genomes)
# Now run directly:
# bash blacklister.sh
# Or run via SLURM scheduler if available
# srun -c 12 bash blacklister.sh


version=0.11

## Modify this section
thr=56
# Reference

ref=/lager2/rcug/seqres/metagenref/bowtie2/refSeqs_allKingdoms_2020_03.fa
#ref=/lager2/rcug/seqres/metagenref/bowtie2/Virus_Fungi3.fasta
#ref=/lager2/rcug/seqres/metagenref/bowtie2/mm10_plus_ASF.fasta
#ref=/lager2/rcug/seqres/HS/human_g1k_v37.fasta
#ref=/lager2/rcug/seqres/metagenref/bwa/refSeqs_allKingdoms_201910_3.fasta
#ref=test/achrom.fa
#ref=test/2sp.fa
#ref=test/2sp_univec.fa


# Input FASTA adapters
#input=adapters.fa
input=/lager2/rcug/seqres/contaminants/2020_02/univec/UniVec_Core.fasta
#input=test/UniVec_Core2_cln.fasta



## Do not change from here on !

## Changelog
# 0.11 - add bowtie2 refSeqs_allKingdoms_201910_3.fasta index
# 0.10 - first commits


# BWA - not suitable!
#bwa mem -a -V -t $thr  test/achrom.fa adapters.fa > test.sam
#bwa mem -a -V -t $thr $ref $input  | samtools view -@ 8 -bhS - | samtools sort -  > test.s.bam
#samtools index test.s.bam
#samtools idxstats test.s.bam > test.s.bam.txt
#samtools view -h test.s.bam > test.sam

echo "INFO: Starting blacklister version: " $version

# bowtie2
echo "INFO: Aligning with bowtie and samtools BAM conversion. Input: " $input " Ref: "  $ref
bowtie2 -p $thr --all -f -x $ref -U $input  | samtools view -@ 8 -bhS - | samtools sort -  > bt.test.s.bam

echo "INFO: Started samtools index and idxstats"
samtools index bt.test.s.bam
samtools idxstats bt.test.s.bam > bt.test.s.bam.txt
samtools view -h bt.test.s.bam > bt.test.sam


# bedtools
echo "INFO: Converting bam to bed"
bedtools bamtobed -ed -i bt.test.s.bam > bt.test.s.bam.bed


# maskfasta
echo "INFO: Creating masked FASTA output: " $ref.masked.fa
bedtools maskfasta -fi $ref -bed bt.test.s.bam.bed -fo $ref.masked.fa




echo "INFO: stats before masking - check Ns"
stats.sh $ref
echo "INFO: stats after masking - check Ns"
stats.sh $ref.masked.fa



# Checks
echo "INFO: Number of lines in files. Only regions in bed file are used for masking ! "
wc -l *.sam
echo "INFO: Number of lines in SAM file without headers "
grep -v "@SQ" *.sam | grep -v "@PG" | wc -l
echo "INFO: Number of lines in output bed file, should be very similar to above line! "
wc -l *.bed

echo "INFO: Number of lines with 3 Ns NNN before masking "
grep -c NNN $ref
echo "INFO: Number of lines with 3 Ns NNN after masking "
grep -c NNN $ref.masked.fa


echo "INFO: Blacklister complete"
