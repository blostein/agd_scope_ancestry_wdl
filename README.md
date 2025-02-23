# SCOPE WDL & Docker image

## Creating a docker image for Scope

- https://github.com/sriramlab/SCOPE
    - Dependencies: 
        - g++ (>=4.5)
        - cmake (>=2.8.12)
        - make (>=3.81)
- First git clone SCOPE: 
    - git clone https://github.com/sriramlab/SCOPE.git
    - NOTE see issue https://github.com/sriramlab/SCOPE/issues/5 had to remove SSE references in mailman.h to get to run 
    - did this manually -- commented out the specified lines 
- Docker build approach: https://www.jmoisio.eu/en/blog/2020/06/01/building-cpp-containers-using-docker-and-cmake/
    docker build -t blosteinf/scope:0.1 .
PROBLEM: wrong architecture on my M1 laptop, see issue here: https://support.terra.bio/hc/en-us/community/posts/5877050265115-docker-run-exec-format-error
SOLUTION: multiplatform build, see: https://blog.jaimyn.dev/how-to-build-multi-architecture-docker-images-on-an-m1-mac/ AND
https://github.com/moby/buildkit/issues/2343
https://stackoverflow.com/questions/20481225/how-can-i-use-a-local-image-as-the-base-image-with-a-dockerfile


    docker buildx build --platform linux/amd64 -t blosteinf/scope:0.1 .
    docker run -it blosteinf/scope:0.1
    docker push blosteinf/scope:0.1

    docker buildx create --use
    docker buildx build --platform linux/amd64,linux/arm64 --push -t blostein/scope:0.1 .
    docker buildx build --push --tag blosteinf/scope:0.1 --platform=linux/arm64,linux/amd64 .
    
    Now it exists here: https://hub.docker.com/r/blosteinf/scope


## Using the WDL work flow for estimating ancestry 

## Running in Terra: Input notes 

### Required inputs

- Start with a Array of chromosome inputs such as can be created using the VUMCFileSize WDL script, see tutorial for VUMC Terra page, selectiing the chromosomes you want to use for ancestry estimation
    - i.e., https://sites.google.com/view/biovu/gwas-analysis/2-prepare-genotype-data
    - Select the output for this as your input: i.e. appropriate an example of this would be select data table agd_35k_all_set and agd35k_pca_gbmi_input_no_XYM_2024-06-17
    - This is what you will use for input chromosome, source_{pgen/pvar/psam}_files
- A random seed 
- The GRID IID conversion file: e.g. "gs://working-set-redeposit/ica-agd/cohort_001/20240303_agd35k_ica_primary_eligible.txt"
- A file with long range LD variants to exclude. I used the GrCH38 positions listed here: https://genome.sph.umich.edu/wiki/Regions_of_high_linkage_disequilibrium_(LD)

### Highly recommended but listed as optional, has default.

- plink2_LD_filter_option: Additional filtering options for plink. Highly recommend at least some to subset the number of variants going in to the analysis. Scopes UK biobank used "--maf 0.01 --indep-pairwise 50 kb 80 0.1" as this is what SCOPE paper did for their UKB analysis, but because plink2 will not allow this a step size of 1 when the KB option is used, and because we ended up with lots of SNPs for MAF 0.01 and SCOPE also used 0.05 for another dataset, the default here is "--maf 0.05 --indep-pairwise 50 1 0.1"

- Memory usage: When using smaller SNP sets such as the UK Biobank’s PCA set (147,604 SNPs), SCOPE uses about 60 GB of memory (488,363 individuals and 147,604 SNPs). So for our 35k individuals, start with 20 and scale up if need, readjust for 250k set. You can change the parameter memory_gb for each subtask in the WDL script, including for RunScopeSupervised and RunScopeUnsupervised.

- The disk size for ConvertPgentoBed is doubled from the usual, because this failed in my first run 


### Supervised versus unsupervised estimation 

- This can be run either unsupervised or both supervised and unsupervised. To include a supervised run, you MUST include the frequncy file of allele frequencies in a specified population. This parameter is optional in the WDL script, and if it exists, then the Supervised function will run. 
   - The frequency file is a tab-delimited file with the following columns: CHR SNP CLST A1 A2 MAF MAC NCHROBS 
   - You can see an example of how I generated this using the thousand genomes project (TGP) data in the TGP_supervised_frequencies directiory, script download_prune_topmed.sh. This script downloads the TGP dta following the script provided in the SCOPE github real_data github directory. Because that TGP was on a different chromosome build than AGD, the tool liftOver was used to convert to the AGD build (GCh38). Then the within population frequencies were calculated 


Note: The WDL script has a hard time locating the localized files, so I used symbolic links, a la https://support.terra.bio/hc/en-us/community/posts/360077616291-Cromwell-question-localization-of-reference-files
