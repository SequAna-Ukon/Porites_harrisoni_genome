#!/bin/bash

conda activate annotation
conda install -c bioconda trnascan-se
conda install -c bioconda star
conda install -c bioconda samtools
conda install -c bioconda agat
conda install -c bioconda gffread
conda install -c bioconda trimmomatic

# # tRNA PREDICTION # #
tRNAscan-SE -E -I -H --detail --thread 50 -o trnascan-se.out -f trnascan-se.tbl -m trnascan-se.log  PAG_UKon_Phar_1.1.fasta.masked
EukHighConfidenceFilter -i trnascan-se.out -s trnascan-se.tbl -o eukconf -p filt

# # TRIM RNASeq reads # #
INDIR="/path/to/raw_rnaseq"
OUTDIR="/path/to/trimmed_rnaseq"

for file in $INDIR/*_R1.fastq.gz; do 
  base=$(basename $file _R1.fastq.gz)
  trimmomatic PE -threads 32 \
  $INDIR/${base}_R1.fastq.gz \
  $INDIR/${base}_R2.fastq.gz \
  $OUTDIR/${base}_trimmed_1P.fastq.gz $OUTDIR/${base}_trimmed_1U.fastq.gz \
  $OUTDIR/${base}_trimmed_2P.fastq.gz $OUTDIR/${base}_trimmed_2U.fastq.gz \
  ILLUMINACLIP:all_truseq_edited.fasta:2:30:10 LEADING:3 TRAILING:3 SLIDINGWINDOW:4:20 MINLEN:50
done

# # RNASeq mapping # #
STAR --runThreadN 50 --runMode genomeGenerate --genomeDir Phar_index --genomeFastaFiles PAG_UKon_Phar_1.1.fasta --genomeSAindexNbases 10

for i in `ls *1P.fq.gz|sed 's/_1P.fq.gz//g'`; do 
    STAR --runThreadN 50 \
    --genomeDir Phar_index \
    --readFilesIn ${i}_1P.fq.gz ${i}_2P.fq.gz \
    --readFilesCommand "zcat" \
    --outSAMtype  BAM SortedByCoordinate \
    --outSAMstrandField intronMotif \
    --twopassMode Basic \
    --outFileNamePrefix ${i}_ \
    --limitBAMsortRAM 10000000000
done

samtools merge -@ 50 Phar_RNASeqAll.STAR.bam *.sortedByCoord.out.bam

####### THIS IS ONLY IF RNASeq ARE REVERSE STRANDED #######

# # SPLIT STRANDED RNASeq BAM FILE # # 

# Plus strand
samtools view -h Phar_RNASeqAll.STAR.bam | awk 'BEGIN{OFS="\t"} /^@/ || ($2==99 || $2==83)' | samtools view -b -o Phar_plus_strand.bam

# Minus strand
samtools view -h Phar_RNASeqAll.STAR.bam | awk 'BEGIN{OFS="\t"} /^@/ || ($2==147 || $2==163)' | samtools view -b -o Phar_minus_strand.bam

##############################################################

# BRAKER3 (https://github.com/Gaius-Augustus/BRAKER)
sudo docker run --user 1000:100  -v $(pwd):/home/jovyan/work  teambraker/braker3:latest braker.pl --species=Porites_harrisoni --genome=work/PAG_UKon_Phar_1.1.fasta.masked --bam=work/Phar_plus_strand.bam,work/Phar_minus_strand.bam --stranded=+,- --threads 50 --prot_seq=work/Metazoa.fa --busco_lineage=metazoa_odb10

# # UTRs # #
pip install intervaltree
python3.8 ../stringtie2utr.py -g braker.gtf -s GeneMark-ETP/rnaseq/stringtie/transcripts_merged.gff -o braker_with_utrs.gtf
# The script currently resides here: https://github.com/Gaius-Augustus/BRAKER/blob/utr_from_stringtie/scripts/stringtie2utr.py

# # IMPLEMENT tRNA PREDICTION # #

# covert tRNA to gff after removing non-high confident
perl convert_tRNAScanSE_to_gff3.pl --input=filter.out > trna_annotation.gff

# gtf to gff
cat braker/braker_with_utrs.gtf | gtf2gff.pl --gff3 -o braker.gff3

# merge gff files
agat_sp_merge_annotations.pl --gff braker.gff3 --gff trna_annotation.gff --out merged.gff

# export protein sequences to proceed with functional annotation
gffread merged.gff -g PAG_UKon_Phar_1.1.fasta -y Phar.braker.prot.fasta

# # CHECK FOR OVERLAPPING GENES # # 
agat_sp_fix_overlaping_genes.pl -f merged.gff -o PAG_Phar_UKon_1.1.gff3

# # VALIDATE GFF3 FILE # # 
gt gff3validator PAG_Phar_UKon_1.1.gff3
