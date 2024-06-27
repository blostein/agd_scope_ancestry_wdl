#!/bin/env bash

ml  PLINK/1.9b_5.2
ml VCFtools/0.1.16

cd /data/davis_lab/blostein/agd_qc/topmed_scope
# Download TGP - note that these from Scope paper are from Build 37 
wget ftp://ftp.1000genomes.ebi.ac.uk/vol1/ftp/technical/working/20120131_omni_genotypes_and_intensities/Omni25_genotypes_2141_samples.b37.vcf.gz
wget https://raw.githubusercontent.com/sriramlab/SCOPE/d74a181d5102b1eff6a55ee5dc4cebd2dba1c554/misc/real_data/TGP/tgp_pops.txt
wget https://raw.githubusercontent.com/sriramlab/SCOPE/d74a181d5102b1eff6a55ee5dc4cebd2dba1c554/misc/real_data/TGP/TGP_unrel.txt
wget https://raw.githubusercontent.com/sriramlab/SCOPE/d74a181d5102b1eff6a55ee5dc4cebd2dba1c554/misc/real_data/TGP/tgp_super_pops.txt

# Convert to PLINK format, remove related individuals, MAF filter
vcftools --gzvcf Omni25_genotypes_2141_samples.b37.vcf.gz --keep TGP_unrel.txt --maf 0.01 --max-missing 0.95 --max-alleles 2 --min-alleles 2 --chr 1 --chr 2 --chr 3 --chr 4 --chr 5 --chr 6 --chr 7 --chr 8 --chr 9 --chr 10 --chr 11 --chr 12 --chr 13 --chr 14 --chr 15 --chr 16 --chr 17 --chr 18 --chr 19 --chr 20 --chr 21 --chr 22 --plink-tped --out TGP_plink

# Convert to PLINK BED/BIM/FAM
plink --tfile TGP_plink --make-bed --out TGP_1718

# Calculate frequencies and get FST
plink --bfile TGP_1718 --freq --out tgp_freqs
plink --bfile TGP_1718 --freq --within tgp_super_pops.txt --out tgp_freqs_within

#FST stats
plink --bfile TGP_1718 --fst --within tgp_pops.txt --out tgp_pops
plink --bfile TGP_1718 --fst --within tgp_super_pops.txt --out tgp_super_pops

#download lift over and install --- its just an executable
ml PLINK/2.00-alpha2
#use plink2 do convert ids 

plink2 --bfile TGP_1718 --set-all-var-ids @:# --make-bed --out TGP_1718_renamed

# now apply lift over 
ml purge
ml load PLINK/1.9b_5.2 GCCcore/.8.2.0 Python/2.7.15

# first, we need to get to the point that we 

plink --bfile TGP_1718_renamed --recode --out TGP_1718_lift
awk '{print "M",$2}' TGP_1718_lift.map > TGP_1718_lift.dat
echo -e "CHR POS" | cat - TGP_1718_lift.dat > headed_TGP_1718_lift.dat
/data/davis_lab/shared/gnomAD/LiftOver/liftOverPlink.py -m TGP_1718_lift.map -p TGP_1718_lift.ped  -d headed_TGP_1718_lift.dat -o TYP_1718_lift_int -c /data/davis_lab/shared/gnomAD/LiftOver/hg38ToHg19.over.chain.gz -e /data/davis_lab/shared/gnomAD/LiftOver/liftOver
echo STEP 5 of 8: Removing bad lifts
/data/davis_lab/shared/gnomAD/LiftOver/rmBadLifts.py -m TYP_1718_lift_int.map  -o TYP_1718_lift_int_badmapsremoved.map -l int_TYP_1718_lift_badmaps
#Only keep the non-bad lifts
awk '{print $2}' TYP_1718_lift_int_badmapsremoved.map > int_snplist.txt
plink --file TYP_1718_lift_int --extract int_snplist.txt --allow-extra-chr --make-bed --out TYP_1718_lift_int_complete
#generate the final file 
mv TYP_1718_lift_int_complete.bim TYP_1718_lift_int_complete_OG.bim
awk '{print $1,$1":"$4,$3,$4,$5,$6}' TYP_1718_lift_int_complete_OG.bim > TYP_1718_lift_int_complete.bim

#after lift over, recalculate the frequencies with these new IDS post lift over to GRCH38
plink --bfile TYP_1718_lift_int_complete --freq --within tgp_super_pops.txt --out tgp_38_freqs_within

