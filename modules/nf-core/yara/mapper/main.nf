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
        yara_mapper \\
            $args \\
            -t $task.cpus \\
            -f bam \\
            ${index_prefix} \\
            $reads | samtools view -@ $task.cpus -hb -F4 | samtools sort -@ $task.cpus > ${prefix}.mapped.bam

        samtools index -@ $task.cpus ${prefix}.mapped.bam

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            yara: \$(echo \$(yara_mapper --version 2>&1) | sed 's/^.*yara_mapper version: //; s/ .*\$//')
            samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//')
        END_VERSIONS
        """
    } else {
        """
        # Fusion 2.x uses /tmp/ as its NVMe disk cache layer and intercepts ALL I/O
        # beneath that path — not only files explicitly staged under /fusion/s3/.
        # SeqAn2's file_async.h (used by yara_mapper) creates anonymous O_TMPFILE
        # descriptors in the process CWD or TMPDIR (both of which default to /tmp/).
        # Fusion intercepts these fds and hits a SetAttr state-corruption bug:
        #   resize(4, 256) failed: "No such file or directory" → SIGABRT (exit 134)
        #
        # Fix: stage inputs and redirect TMPDIR to /var/tmp/ (EBS root volume),
        # which is outside Fusion's FUSE mount and has sufficient space for large
        # FASTQ files. /dev/shm (RAM-backed) is also outside Fusion's scope but
        # is typically too small for multi-GB FASTQ pairs.
        LOCAL=\$(mktemp -d -p /var/tmp)
        export TMPDIR=\${LOCAL}

        cp ${reads[0]} \${LOCAL}/read1.fastq.gz
        cp ${reads[1]} \${LOCAL}/read2.fastq.gz
        cp ${index_prefix}.* \${LOCAL}/

        cd \${LOCAL}
        yara_mapper \\
            $args \\
            -t $task.cpus \\
            -f bam \\
            ${index_prefix} \\
            read1.fastq.gz \\
            read2.fastq.gz > output.bam

        samtools view -@ $task.cpus -hF 4 -f 0x40 -b output.bam | samtools sort -@ $task.cpus > ${prefix}_1.mapped.bam
        samtools view -@ $task.cpus -hF 4 -f 0x80 -b output.bam | samtools sort -@ $task.cpus > ${prefix}_2.mapped.bam

        mv ${prefix}_1.mapped.bam ${prefix}_2.mapped.bam \${OLDPWD}/
        cd \${OLDPWD}

        rm -rf \${LOCAL}

        samtools index -@ $task.cpus ${prefix}_1.mapped.bam
        samtools index -@ $task.cpus ${prefix}_2.mapped.bam

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            yara: \$(echo \$(yara_mapper --version 2>&1) | sed 's/^.*yara_mapper version: //; s/ .*\$//')
            samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//')
        END_VERSIONS
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
