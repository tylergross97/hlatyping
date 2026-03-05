process YARA_MAPPER {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/mulled-v2-f13549097a0d1ca36f9d4f017636fb3609f6c083:de7982183b85634270540ac760c2644f16e0b6d1-0' :
        'biocontainers/mulled-v2-f13549097a0d1ca36f9d4f017636fb3609f6c083:de7982183b85634270540ac760c2644f16e0b6d1-0' }"

    input:
    tuple val(meta), path(reads)
    tuple val(meta2), path(index)

    output:
    tuple val(meta), path("*.mapped.bam")    , emit: bam
    tuple val(meta), path("*.mapped.bam.bai"), emit: bai
    path "versions.yml"                      , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def index_prefix = index[0].baseName.substring(0,index[0].baseName.lastIndexOf('.'))
    if (meta.single_end) {
        """
        # CRITICAL FUSION WORKAROUND: Copy all inputs to /tmp and work there
        # YARA creates temp files in the current directory which triggers Fusion bugs
        # when the work directory is S3-mounted. Solution: work entirely in local /tmp
        
        mkdir -p /tmp/yara_work
        cd /tmp/yara_work
        
        # Copy inputs to local storage
        cp -L ${index_prefix}.* . || true
        cp -L $reads reads_single.fq.gz
        
        # Get the base name of the index for yara_mapper
        INDEX_BASE=\$(basename ${index_prefix})
        
        # Run YARA entirely in local /tmp directory
        yara_mapper \\
            $args \\
            -t $task.cpus \\
            -f bam \\
            \${INDEX_BASE} \\
            reads_single.fq.gz | samtools view -@ $task.cpus -hb -F4 | samtools sort -@ $task.cpus > ${prefix}.mapped.bam

        samtools index -@ $task.cpus ${prefix}.mapped.bam

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            yara: \$(echo \$(yara_mapper --version 2>&1) | sed 's/^.*yara_mapper version: //; s/ .*\$//')
            samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//')
        END_VERSIONS
        
        # Copy outputs back to work directory (Nextflow will stage them automatically)
        # No explicit copy needed - outputs are already in /tmp/yara_work which is our CWD
        """
    } else {
        """
        # CRITICAL FUSION WORKAROUND: Copy all inputs to /tmp and work there
        # YARA creates temp files in the current directory which triggers Fusion bugs
        # when the work directory is S3-mounted. Solution: work entirely in local /tmp
        
        mkdir -p /tmp/yara_work
        cd /tmp/yara_work
        
        # Copy inputs to local storage
        cp -L ${index_prefix}.* . || true
        cp -L ${reads[0]} reads_R1.fq.gz
        cp -L ${reads[1]} reads_R2.fq.gz
        
        # Get the base name of the index for yara_mapper
        INDEX_BASE=\$(basename ${index_prefix})
        
        # Run YARA entirely in local /tmp directory
        yara_mapper \\
            $args \\
            -t $task.cpus \\
            -f bam \\
            \${INDEX_BASE} \\
            reads_R1.fq.gz \\
            reads_R2.fq.gz > output.bam

        # Process BAM files
        samtools view -@ $task.cpus -hF 4 -f 0x40 -b output.bam | samtools sort -@ $task.cpus > ${prefix}_1.mapped.bam
        samtools view -@ $task.cpus -hF 4 -f 0x80 -b output.bam | samtools sort -@ $task.cpus > ${prefix}_2.mapped.bam

        samtools index -@ $task.cpus ${prefix}_1.mapped.bam
        samtools index -@ $task.cpus ${prefix}_2.mapped.bam

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            yara: \$(echo \$(yara_mapper --version 2>&1) | sed 's/^.*yara_mapper version: //; s/ .*\$//')
            samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//')
        END_VERSIONS
        
        # Copy outputs back to work directory (Nextflow will stage them automatically)
        # No explicit copy needed - outputs are already in /tmp/yara_work which is our CWD
        """
    }

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def index_prefix = index[0].baseName.substring(0,index[0].baseName.lastIndexOf('.'))
    if (meta.single_end) {
        """
        touch ${prefix}.mapped.bam
        touch ${prefix}.mapped.bam.bai

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            yara: \$(echo \$(yara_mapper --version 2>&1) | sed 's/^.*yara_mapper version: //; s/ .*\$//')
            samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//')
        END_VERSIONS
        """
    } else {
        """
        touch ${prefix}_1.mapped.bam
        touch ${prefix}_2.mapped.bam.bai

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            yara: \$(echo \$(yara_mapper --version 2>&1) | sed 's/^.*yara_mapper version: //; s/ .*\$//')
            samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//')
        END_VERSIONS
        """
    }

}
