process IMAGE_INFO {
    tag "$meta.id"
    label 'process_single'

    container "mrtrix3/mrtrix3:3.0.5"

    input:
    tuple val(meta), path(image)

    output:
    tuple val(meta), stdout , emit: property
    path "versions.yml"                        , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def property = task.ext.property ? "-${task.ext.property}" : '-all' // REQUIRED.

    """
    mrinfo ${image} ${property}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mrinfo: \$(mrinfo -version 2>&1 | sed -n 's/== mrinfo \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """

    stub:
    def property = task.ext.property ? "-${task.ext.property}" : '-all' // REQUIRED.
    """
    echo "Some property values for ${image} with ${property}"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mrinfo: \$(mrinfo -version 2>&1 | sed -n 's/== mrinfo \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """
}
