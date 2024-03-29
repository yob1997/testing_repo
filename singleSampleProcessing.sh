#!/bash/bin

singleSampleProcessing () {
  local R1=$1;local R2=$2; local ref=$3; local reads=$4
  local sample=$(echo ${R1} | cut -d_ -f1,2)
  local outdir=genome_data/toolOut/aligned_bwa/$sample
  mkdir -p $outdir
  
  # return if last output file of the function is already created
  if [ -s $outdir/$sample.g.vcf.gz ];then
    echo "gVCF already created for $sample."
    return
  fi

##~~~~ BWA MEM: map to reference / samtools: view transform to .bam ~~~~##
  if [ ! -f $outdir/$sample.bwa.bam ];then
    bwa mem -M -t 8 $ref $reads$R1 $reads$R2 | samtools view -@ 8 -bS - > $outdir/$sample.bwa.bam
  fi

##~~~~ Picard: RevertSam to create uBAM ~~~~## 
  if [ ! -s $outdir/$sample.bwa.u.bam ];then
    java -Xmx20g -XX:ParallelGCThreads=8 -jar tools/picard.jar RevertSam \
      I=$outdir/$sample.bwa.bam \
      O=$outdir/$sample.bwa.u.bam \
      ATTRIBUTE_TO_CLEAR=XS \
      ATTRIBUTE_TO_CLEAR=XA QUIET=true
  fi
  
##~~~~ Picard: AddOrReplaceReadGroups information to uBAM ~~~~## 
  if [ ! -s $outdir/$sample.bwa.rg.bam ];then
    java -Xmx20g -XX:ParallelGCThreads=8 -jar tools/picard.jar AddOrReplaceReadGroups \
      I=$outdir/$sample.bwa.u.bam \
      O=$outdir/$sample.bwa.rg.bam \
      RGID=$sample RGSM=$sample RGLB=wgsim RGPU=shlee RGPL=illumina QUIET=true
  fi

##~~~~ Picard: MergeBamAlignment merge uBAM with aligned BAM ~~~~##
  if [ ! -s $outdir/$sample.bwa.m.bam ];then
  java -Xmx20g -XX:ParallelGCThreads=8 -jar tools/picard.jar MergeBamAlignment \
    ALIGNED=$outdir/$sample.bwa.bam \
    UNMAPPED=$outdir/$sample.bwa.rg.bam \
    O=$outdir/$sample.bwa.m.bam \
    R=$ref \
    SORT_ORDER=unsorted CLIP_ADAPTERS=false \
    ADD_MATE_CIGAR=true \
    MAX_INSERTIONS_OR_DELETIONS=-1 \
    PRIMARY_ALIGNMENT_STRATEGY=MostDistant \
    UNMAP_CONTAMINANT_READS=false \
    ATTRIBUTES_TO_RETAIN=XS \
    ATTRIBUTES_TO_RETAIN=XA QUIET=true
  fi
  
##~~~~ Picard: MarkDuplicates Flag duplicate reads ~~~~##  
  if [ ! -s $outdir/$sample.bwa.md.bam ];then
    java -Xmx20g -XX:ParallelGCThreads=8 -jar tools/picard.jar MarkDuplicates \
      INPUT=$outdir/$sample.bwa.m.bam \
      OUTPUT=$outdir/$sample.bwa.md.bam \
      METRICS_FILE=$outdir/$sample.bwa.md.bam.txt \
      OPTICAL_DUPLICATE_PIXEL_DISTANCE=2500 ASSUME_SORT_ORDER=queryname QUIET=true
  fi
  
##~~~~ Picard: SortSam Coordinate sort, fix NM, UQ tags and index for clean BAM ~~~~## 
  if [ ! -s $outdir/$sample.snaut.bam ];then
    set -o pipefail
    java -Xmx20g -XX:ParallelGCThreads=8 -jar tools/picard.jar SortSam \
      INPUT=$outdir/$sample.bwa.md.bam \
      OUTPUT=/dev/stdout SORT_ORDER=coordinate | \
      java -jar tools/picard.jar SetNmMdAndUqTags \
      INPUT=/dev/stdin \
      OUTPUT=$outdir/$sample.snaut.bam \
      CREATE_INDEX=true R=$ref QUIET=true
  fi
  
##~~~~ GATK: HaplotypeCaller create gVCF~~~~##  
#// QUESTION: should I set -ploidy 1, because the K. pneumoniae only has one chromosome. How does this affect the 5 plasmids in the data?
  #  Call SNP and indel variants in emit reference confidence (ERC) mode per sample using HaplotypeCaller
  if [ ! -s $outdir/$sample.g.vcf.gz ];then
    java -Xmx20g -jar tools/gatk-4.1.3.0/gatk-package-4.1.3.0-local.jar HaplotypeCaller \
    -R $ref \
    -O $outdir/$sample.g.vcf \
    -I $outdir/$sample.snaut.bam \
    -ERC GVCF \
    --native-pair-hmm-threads 8 \
    -ploidy 1 \
    --QUIET true
    bgzip $outdir/$sample.g.vcf
    tabix -p vcf $outdir/$sample.g.vcf.gz
    
  fi
  
  if [ -s $outdir/$sample.g.vcf.gz ];then
      echo "removing temporary alignment files"
      rm -f $outdir/$sample.bwa.bam $outdir/$sample.bwa.u.bam $outdir/$sample.bwa.rg.bam $outdir/$sample.bwa.m.bam \
      $outdir/$sample.bwa.md.bam $outdir/$sample.bwa.m.bam $outdir/$sample.bwa.md.bam 
  fi
}

export -f singleSampleProcessing

singleSampleProcessing "$1" "$2" "$3" "$4"







