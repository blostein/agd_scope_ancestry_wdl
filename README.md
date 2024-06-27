# SCOPE WDL & Docker image

## Creating a docker image for Scope

- https://github.com/sriramlab/SCOPE
    - Dependencies: 
        - g++ (>=4.5)
        - cmake (>=2.8.12)
        - make (>=3.81)
- Approach: https://www.jmoisio.eu/en/blog/2020/06/01/building-cpp-containers-using-docker-and-cmake/
    - First git clone SCOPE: 
        - git clone https://github.com/sriramlab/SCOPE.git
    - Two step approach: 
        - Build docker with dependencies
            - For right now trying without specifying versions for g++ and cmake, 
            - but could using this: `apt-get install -y g++=4.5 cmake=2.8.12 make=3.81`
        - Deploy docker  

NOTE see issue https://github.com/sriramlab/SCOPE/issues/5 had to remove SSE references in mailman.h to get to run 
 did this manually -- commented out the specified lines 

docker build -t blosteinf/scope:0.1 .

docker run -it blosteinf/scope:0.1
docker push blosteinf/scope:0.1

Now it exists here: https://hub.docker.com/r/blosteinf/scope


## Creating a WDL for SCOPE analysis

Approach: 

Scatter, replace ID with GRID, MAF + snp only filter + LD prune + remove long range LD

merge 

convert to bed https://github.com/UW-GAC/primed-file-conversion/blob/main/plink2_pgen2bed.wdl
run scope unsupervised

if a frequency file is present, run supervised

memory usage: When using smaller SNP sets such as the UK Biobank’s PCA set (147,604 SNPs), SCOPE uses about 60 GB of memory (488,363 individuals and 147,604 SNPs).

so for our 35k individuals, start with 20 and scale up if need, readjust for 250k set
