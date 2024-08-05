version 1.0

#IMPORTS
## According to this: https://cromwell.readthedocs.io/en/stable/Imports/ we can import raw from github
## so we can make use of the already written WDLs provided by WARP/VUMC Biostatistics

import "https://raw.githubusercontent.com/shengqh/warp/develop/tasks/vumc_biostatistics/GcpUtils.wdl" as http_GcpUtils
import "https://raw.githubusercontent.com/shengqh/warp/develop/pipelines/vumc_biostatistics/genotype/Utils.wdl" as http_GenotypeUtils
import "https://raw.githubusercontent.com/shengqh/warp/develop/pipelines/vumc_biostatistics/agd/AgdUtils.wdl" as http_AgdUtils

workflow TGP_getFreqs{
    input{
        File source_pgen_file
        File source_pvar_file
        File source_psam_file

        File source_superpop_file        
        
        String? project_id
        String? target_gcp_folder
    }

    call CalculateFreq{
        input: 
            pgen_file = source_pgen_file,
            pvar_file = source_pvar_file,
            psam_file = source_psam_file,
            superpop_file = source_superpop_file
    }

    if(defined(target_gcp_folder)){
        call http_GcpUtils.MoveOrCopyOneFile as CopyFile{
            input:
                source_file = CalculateFreq.freq_file,
                is_move_file = false,
                project_id = project_id,
                target_gcp_folder = select_first([target_gcp_folder])
        }
    }

    output {
        File output_tgp_freq_file = select_first([CopyFile.output_file, CalculateFreq.freq_file])
    }
    
}

# tasks

task CalculateFreq{
    input{ 
        File pgen_file
        File pvar_file
        File psam_file
        File superpop_file

        Int memory_gb = 20
        String docker = "hkim298/plink_1.9_2.0:20230116_20230707"
    }

    Int disk_size = ceil(size([pgen_file, psam_file, pvar_file], "GB")  * 2) + 20

    command <<<
        plink2 --pgen ~{pgen_file} \
            --pvar ~{pvar_file} \
            --psam ~{psam_file} \
            --rm-dup 'exclude-all' \
            --make-bed \
            --out tgp_nodup  

        plink --bfile tgp_nodup \
            --freq --within ~{superpop_file} \
            --out tgp_within_superpop_freqs
    >>>

    runtime {
        docker: docker
        preemptible: 1
        disks: "local-disk " + disk_size + " HDD"
        memory: memory_gb + " GiB"
    }

    output{
        File freq_file = "tgp_within_superpop_freqs.frq"
    }
}