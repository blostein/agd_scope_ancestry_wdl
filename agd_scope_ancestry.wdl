version 1.0

#IMPORTS
## According to this: https://cromwell.readthedocs.io/en/stable/Imports/ we can import raw from github
## so we can make use of the already written WDLs provided by WARP/VUMC Biostatistics

import "https://raw.githubusercontent.com/shengqh/warp/develop/tasks/vumc_biostatistics/GcpUtils.wdl" as http_GcpUtils
import "https://raw.githubusercontent.com/shengqh/warp/develop/pipelines/vumc_biostatistics/genotype/Utils.wdl" as http_GenotypeUtils
import "https://raw.githubusercontent.com/shengqh/warp/develop/pipelines/vumc_biostatistics/agd/AgdUtils.wdl" as http_AgdUtils

workflow VUMCscope {
  input {
        Array[File] source_pgen_files
        Array[File] source_pvar_files
        Array[File] source_psam_files

        Array[String] chromosomes

        String target_prefix

        String? plink2_maf_filter = "--maf 0.01"

        String? plink2_LD_filter_option = "--indep-pairwise 50000 80 0.1"
        File long_range_ld_file

        File? topmed_freq
        Int K = 4
        Int seed 

        File id_map_file
        

        String? project_id
        String? target_gcp_folder
    }

    scatter (idx in range(length(chromosomes))) {
        String chromosome = chromosomes[idx]
        File pgen_file = source_pgen_files[idx]
        File pvar_file = source_pvar_files[idx]
        File psam_file = source_psam_files[idx]
        String replaced_sample_name = "~{chromosome}.psam"

        #I think I need this to get the IDs correctly as GRIDS

        call http_AgdUtils.ReplaceICAIdWithGrid as ReplaceICAIdWithGrid {
        input:
            input_psam = psam_file,
            id_map_file = id_map_file,
            output_psam = replaced_sample_name
        }
        call PreparePlink as PreparePlink{
            input:
                pgen_file = pgen_file,
                pvar_file = pvar_file,
                psam_file = ReplaceICAIdWithGrid.output_psam,
                long_range_ld_file = long_range_ld_file,
                plink2_maf_filter = plink2_maf_filter,
                plink2_LD_filter_option = plink2_LD_filter_option,
                chromosome = chromosome 
        }
    }
    call http_GenotypeUtils.MergePgenFiles as MergePgenFiles{
        input:
            pgen_files = PreparePlink.output_pgen_file,
            pvar_files = PreparePlink.output_pvar_file,
            psam_files = PreparePlink.output_psam_file,
            target_prefix = target_prefix
  }

  call ConvertPgenToBed{
    input: 
        pgen = MergePgenFiles.output_pgen_file, 
        pvar = MergePgenFiles.output_pvar_file,
        psam = MergePgenFiles.output_psam_file, 
  }

  call RunScopeUnsupervised{    
    input:
        bed_file = ConvertPgenToBed.out_bed,
        bim_file = ConvertPgenToBed.out_bim,
        fam_file = ConvertPgenToBed.out_fam,
        K = K,
        output_string = target_prefix,
        seed = seed
  }

  if(defined(topmed_freq)){

    call QCAllelesBim{
        input:
            bim_file = ConvertPgenToBed.out_bim,
            freq_file = topmed_freq
    }

    call PreparePlinkSupervised{
        input:
            bed_file = ConvertPgenToBed.out_bed,
            bim_file = ConvertPgenToBed.out_bim,
            fam_file = ConvertPgenToBed.out_fam,
            variant_list = QCAllelesBim.out_variants
    }

    call RunScopeSupervised{
        input:
            bed_file = PreparePlinkSupervised.out_bed,
            bim_file = PreparePlinkSupervised.out_bim,
            fam_file = PreparePlinkSupervised.out_fam,
            K = K,
            output_string = target_prefix,
            seed = seed,
            topmed_freq = QCAllelesBim.out_frq
        }
    }

    if(defined(target_gcp_folder)){
        call http_GcpUtils.MoveOrCopyThreeFiles as CopyFiles_one{
            input:
                source_file1 = RunScopeUnsupervised.outP,
                source_file2 = RunScopeUnsupervised.outQ,
                source_file3 = RunScopeUnsupervised.outV,
                is_move_file = false,
                project_id = project_id,
                target_gcp_folder = select_first([target_gcp_folder])
            }
        if(defined(topmed_freq)){
            call http_GcpUtils.MoveOrCopyThreeFiles as CopyFiles_two {
                input:
                    source_file1 = select_first([RunScopeSupervised.outP]),
                    source_file2 = select_first([RunScopeSupervised.outQ]),
                    source_file3 = select_first([RunScopeSupervised.outV]),
                    is_move_file = false,
                    project_id = project_id,
                    target_gcp_folder = select_first([target_gcp_folder])
                }
            }
    }
    output {
        File output_PUnsupervised = select_first([CopyFiles_one.output_file1, RunScopeSupervised.outP])
        File output_PSupervised= select_first([CopyFiles_two.output_file1, RunScopeSupervised.outP])
    }
}

## Task DEFINITIONS

task PreparePlink{
  input {
    File pgen_file
    File pvar_file
    File psam_file 

    String chromosome

    String? plink2_maf_filter = "--maf 0.01"
    String? plink2_LD_filter_option = "--indep-pairwise 50000 80 0.1"
    File long_range_ld_file


    Int memory_gb = 20

    String docker = "hkim298/plink_1.9_2.0:20230116_20230707"
  }

  Int disk_size = ceil(size([pgen_file, psam_file, pvar_file], "GB")  * 2) + 20

  String new_pgen = chromosome + ".pgen"
  String new_pvar = chromosome + ".pvar"
  String new_psam = chromosome + ".psam"
  String out_prefix = chromosome 


  command {
    plink2 \
      --pgen ~{pgen_file} \
      --pvar ~{pvar_file} \
      --psam ~{psam_file} \
      ~{plink2_maf_filter} \
      --snps-only \
      --const-fid \
      --set-all-var-ids chr@:#:\$r:\$a \
      --new-id-max-allele-len 1000 \
      --make-pgen \
      --out maf_filtered
      
    plink2 \
        --pgen maf_filtered.pgen \
        --pvar maf_filtered.pvar \
        --psam maf_filtered.psam \
        --exclude range ~{long_range_ld_file} \
        --make-pgen \
        --out maf_filtered_longrange
    
    plink2 \
      --pgen maf_filtered_longrange.pgen \
      --pvar maf_filtered_longrange.pvar \
      --psam maf_filtered_longrange.psam \
      ~{plink2_LD_filter_option}

    plink2 \
        --pgen maf_filtered_longrange.pgen \
        --pvar maf_filtered_longrange.pvar \
        --psam maf_filtered_longrange.psam \
        --extract plink2.prune.in \
        --make-pgen \
        --out ~{out_prefix}
  }

  runtime {
    docker: docker
    preemptible: 1
    disks: "local-disk " + disk_size + " HDD"
    memory: memory_gb + " GiB"
  }

  output {
    File output_pgen_file = new_pgen
    File output_pvar_file = new_pvar
    File output_psam_file = new_psam
  }
}


task QCAllelesBim{
    input {
        File bim_file
        File? freq_file

        String docker = "blosteinf/r_utils_terra:0.1"
        Int memory_gb = 20

    }

    Int disk_size = ceil(size([bim_file, freq_file], "GB")  * 2) + 20

    command {
        ls /home/r-environment/
        Rscript /home/r-environment/allele_qc.R --in_freq ~{freq_file} --in_bim ~{bim_file} 
    }

    runtime {
        docker: docker
        preemptible: 1
        disks: "local-disk " + disk_size + " HDD"
        memory: memory_gb + " GiB"
    }

    output {
        File out_frq = "corrected_freq.frq"
        File out_variants = "variants_to_extract.txt"
    }
}

task PreparePlinkSupervised{
    input { 
        File bed_file
        File bim_file
        File fam_file 

        File variant_list 
        String? out_string = "variant_filtered"

        String docker = "hkim298/plink_1.9_2.0:20230116_20230707"
    }

  Int disk_size = ceil(size([bed_file, bim_file, fam_file], "GB")  * 2) + 20
  Int memory_gb = 20

  String new_bed = out_string + ".bed"
  String new_bim = out_string + ".bim"
  String new_fam= out_string + ".fam"

  command { 
    plink2 \
        --bed ~{bed_file} \
        --bim ~{bim_file} \
        --fam ~{fam_file} \
        --extract ~{variant_list} \
        --make-bed \
        --out ~{out_string}
  }

    runtime {
        docker: docker
        preemptible: 1
        disks: "local-disk " + disk_size + " HDD"
        memory: memory_gb + " GiB"
    }

    output {
        File out_bed = new_bed
        File out_bim = new_bim
        File out_fam = new_fam
        String out_prefix = out_string
    }

}

task RunScopeUnsupervised{
    input{

        File bed_file
        File bim_file
        File fam_file

        Int K
        String output_string
        Int seed

        Int memory_gb = 60
        String docker = "blosteinf/scope:0.1"
    }

    String plink_binary_prefix =  basename(bed_file, ".bed")
    String relocated_bed = plink_binary_prefix + ".bed"
    String relocated_bim = plink_binary_prefix + ".bim"
    String relocated_fam = plink_binary_prefix + ".fam"

    String unsup_output = output_string + "_unsupervised_" 
    Int disk_size = ceil(size([bed_file, bim_file, fam_file], "GB")  * 2) + 20

    command <<<
        ln ~{bed_file} ./~{relocated_bed}
        ln ~{bim_file} ./~{relocated_bim}
        ln ~{fam_file} ./~{relocated_fam}
        scope -g ~{plink_binary_prefix} -k ~{K} -seed ~{seed} -o ~{unsup_output}
        awk '{ for (i=1; i<=NF; i++) { a[NR,i] = $i } } NF>p { p = NF } END { for(j=1; j<=p; j++) { str=a[1,j]; for(i=2; i<=NR; i++) { str=str" "a[i,j]; } print str } }' ~{unsup_output}Qhat.txt > transposed_Qhat.txt
        cut -f2 ./~{relocated_fam} | paste - transposed_Qhat.txt > ~{unsup_output}Qhat.txt
    >>>

    runtime {
        docker: docker
        preemptible: 1
        disks: "local-disk " + disk_size + " HDD"
        memory: memory_gb + " GiB"
  }

    output {
        File outP= "${unsup_output}Phat.txt"
        File outQ= "${unsup_output}Qhat.txt"
        File outV= "${unsup_output}V.txt"
    }
}

task RunScopeSupervised{
    input{
       
        File bed_file
        File bim_file
        File fam_file

        Int K
        String output_string
        Int seed

        File? topmed_freq

        Int memory_gb = 60

        String docker = "blosteinf/scope:0.1"
    }

    String plink_binary_prefix = basename(bed_file, ".bed")
    String relocated_bed= plink_binary_prefix + ".bed"
    String relocated_bim= plink_binary_prefix + ".bim"
    String relocated_fam= plink_binary_prefix + ".fam"

    String sup_output = output_string + "_supervised_"

    Int disk_size = ceil(size([bed_file, bim_file, fam_file], "GB")  * 2) + 20

    command <<<
        ln ~{bed_file} ./~{relocated_bed}
        ln ~{bim_file} ./~{relocated_bim}
        ln ~{fam_file} ./~{relocated_fam}
        scope -g ~{plink_binary_prefix} -freq ~{topmed_freq} -k ~{K} -seed ~{seed} -o ~{sup_output}
        ls
        awk '{ for (i=1; i<=NF; i++) { a[NR,i] = $i } } NF>p { p = NF } END { for(j=1; j<=p; j++) { str=a[1,j]; for(i=2; i<=NR; i++) { str=str" "a[i,j]; } print str } }' ~{sup_output}Qhat.txt > transposed_Qhat.txt
        cut -f2 ./~{relocated_fam} | paste - transposed_Qhat.txt > ~{sup_output}Qhat.txt
    >>>

    runtime {
        docker: docker
        preemptible: 1
        disks: "local-disk " + disk_size + " HDD"
        memory: memory_gb + " GiB"
  }

    output {
        File outP= "${sup_output}Phat.txt"
        File outQ= "${sup_output}Qhat.txt"
        File outV= "${sup_output}V.txt"
    }
}

task ConvertPgenToBed {
    input {
        File pgen 
        File pvar 
        File psam 

        String docker = "hkim298/plink_1.9_2.0:20230116_20230707"

        String? out_prefix

        Int? memory_gb = 20

    }

    Int disk_size = ceil(size([pgen, pvar, psam], "GB")  * 2)*2 + 20


    String out_string = if defined(out_prefix) then out_prefix else basename(pgen, ".pgen")

    command {
        plink2 \
            --pgen ~{pgen} --pvar ~{pvar} --psam ~{psam} \
            --make-bed \
            --out ~{out_string}
    }

    runtime {
        docker: docker
        preemptible: 1
        disks: "local-disk " + disk_size + " HDD"
        memory: memory_gb + " GiB"
    }

    output {
        File out_bed = "${out_string}.bed"
        File out_bim = "${out_string}.bim"
        File out_fam = "${out_string}.fam"
    }
}