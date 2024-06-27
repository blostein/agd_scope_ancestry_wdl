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

        String? plink2_LD_filter_option = "--indep-pairwise 50 kb 80 0.1"
        File long_range_LD_list

        File? topmed_freq
        Int? K = 4
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
                chromosome = chromosome,
                plink2_LD_filter_option = plink2_LD_filter_option,
                long_range_LD_list = long_range_LD_list    
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
        plink_binary_prefix = ConvertPgenToBed.out_string,
        K = K,
        output_string = target_prefix,
        seed = seed
  }

  if(defined(topmed_freq)){
    call RunScopeSupervised{
        input:
            plink_binary_prefix = ConvertPgenToBed.out_string,
            K = K,
            output_string = target_prefix,
            seed = seed
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
            call http_GcpUtils.MoveOrCopyThreeFiles as CopyFiles_two{
                input:
                    source_file1 = RunScopeSupervised.outP,
                    source_file2 = RunScopeSupervised.outQ,
                    source_file3 = RunScopeSupervised.outV,
                    is_move_file = false,
                    project_id = project_id,
                    target_gcp_folder = select_first([target_gcp_folder])
            }
        }
    }
}

## Task DEFINITIONS

task PreparePlink{
  input {
    File pgen_file
    File pvar_file
    File psam_file 

    String chromosome

    File long_range_ld_file
    String plink2_LD_filter_option

    Int memory_gb = 20

    String docker = "hkim298/plink_1.9_2.0:20230116_20230707"
  }

  Int disk_size = ceil(size([pgen_file, psam_file, pvar_file], "GB")  * 2) + 20

  String new_pgen = chromosome + ".pgen"
  String new_pvar = chromosome + ".pvar"
  String new_psam = chromosome + ".psam"


  command {
    plink2 \
      --pgen ~{pgen_file} \
      --pvar ~{pvar_file} \
      --psam ~{psam_file} \
      --snps-only \
      --set-all-var-ids chr@:#:\$r:\$a \
      --new-id-max-allele-len 1000 \
      ~{plink2_LD_filter_option}
      --exclude ~{long_range_ld_file}
      --make-pgen \
      --out ~{chromosome}
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

task RunScopeUnsupervised{
    input{
        String plink_binary_prefix
        Int K
        String output_string
        Int seed

        Int memory_gb = 20
        String docker = "blosteinf/scope:0.1"
    }

    String bed = plink_binary_prefix + ".bed"
    String bim = plink_binary_prefix + ".bim"
    String sam = plink_binary_prefix + ".sam"

    String unsup_output = output_string + "_unsupervised" 
    Int disk_size = ceil(size([bed, bim, sam], "GB")  * 2) + 20

    command {
        scope -g ~{plink_binary_prefix} -k ~{K} -seed ~{seed} -o ~{unsup_output}
    }

    runtime {
        docker: docker
        preemptible: 1
        disks: "local-disk " + disk_size + " HDD"
        memory: memory_gb + " GiB"
  }

    output {
        File outP= "${unsup_output}_Phat.txt"
        File outQ= "${unsup_output}_Qhat.txt"
        File outV= "${unsup_output}_V.txt"
    }
}

task RunScopeSupervised{
    input{
        String plink_binary_prefix
        Int K
        String output_string
        Int seed

        File topmed_freq

        Int memory_gb = 20

        String docker = "blosteinf/scope:0.1"
    }
    String sup_output = output_string + "_supervised"

    File bed_file = plink_binary_prefix + ".bed"
    File bim_file = plink_binary_prefix + ".bim"
    File fam_file = plink_binary_prefix + ".fam"

    Int disk_size = ceil(size([bed_file, bim_file, fam_file], "GB")  * 2) + 20

    command {
        scope -g ~{plink_binary_prefix} --freq ~{topmed_freq} -k ~{K} -seed ~{seed} -o ~{sup_output}
    }

    runtime {
        docker: docker
        preemptible: 1
        disks: "local-disk " + disk_size + " HDD"
        memory: memory_gb + " GiB"
  }

    output {
        File outP= "${sup_output}_Phat.txt"
        File outQ= "${sup_output}_Qhat.txt"
        File outV= "${sup_output}_V.txt"
    }

}

task ConvertPgenToBed {
    input {
        File pgen 
        File pvar 
        File psam 

        String docker = "hkim298/plink_1.9_2.0:20230116_20230707"

        String? out_prefix

    }

    Int disk_size = ceil(size([pgen, pvar, psam], "GB")  * 2) + 20


    String out_string = if defined(out_prefix) then out_prefix else basename(pgen, ".pgen")

    command {
        plink2 \
            --pgen ~{pgen} --pvar ~{pvar} --psam ~{psam} \
            --make-bed \
            --out ${out_string}
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
        String out_string = out_string
    }
}