process IMAGE_INFO {
    tag "$meta.id"
    label 'process_single'

    container "mrtrix3/mrtrix3:3.0.5"

    input:
    tuple val(meta), path(image)

    output:
    tuple val(meta), path("*__*_property.txt") , emit: property
    path "versions.yml"                        , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def property = task.ext.property ? "-${task.ext.property}" : '-all' // REQUIRED.

    """
    mrinfo ${image} ${property} > ${prefix}__${property}_property.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mrinfo: \$(mrinfo -version 2>&1 | sed -n 's/== mrinfo \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def property = task.ext.property ? "-${task.ext.property}" : '-all' // REQUIRED.
    """
    touch ${prefix}__${property}_property.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mrinfo: \$(mrinfo -version 2>&1 | sed -n 's/== mrinfo \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """
}
