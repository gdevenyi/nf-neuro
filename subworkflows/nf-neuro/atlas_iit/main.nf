include { ATLAS_IIT as IIT_BUNDLE_MASKS } from '../../../modules/nf-neuro/atlas/iit/main'

def fetch_iit_atlas_b0(b0Url, dest) {
    def b0 = new File("$dest/IITmean_b0.nii.gz").withOutputStream{ out ->
        new URL(b0Url).withInputStream { from -> out << from; }
    }
    return b0
}

// Fetch Bundles Track Density Maps
// Which are later used to generate bundle masks based on thresholds.
def fetch_iit_atlas_tdi(bundleMapsUrl, dest, thresholds) {
    def output_dir = "${workflow.workDir}/atlas_iit/bundles/tdi/"

    // If files are all there, immediately return the directory
    if (allBundleFilesExist(thresholds, new File(output_dir + "bundle_maps/IIT_bundles"))) {
        return output_dir + "bundle_maps/IIT_bundles"
    }

    def intermediate_dir = new File("$dest/intermediate")
    intermediate_dir.mkdirs()

    new File("$intermediate_dir/IIT_bundles.zip").withOutputStream{ out ->
        new URL(bundleMapsUrl).withInputStream { from -> out << from; }
    }

    def bundleMapsFile = new java.util.zip.ZipFile("$intermediate_dir/IIT_bundles.zip")
    bundleMapsFile.entries().each{ it ->
        def path = java.nio.file.Paths.get("$dest/bundle_maps/" + it.name)
        if (it.directory) {
            java.nio.file.Files.createDirectories(path)
        }
        else {
            def parentDir = path.getParent()
            if (!java.nio.file.Files.exists(parentDir)) {
                java.nio.file.Files.createDirectories(parentDir)
            }
            java.nio.file.Files.copy(bundleMapsFile.getInputStream(it), path)
        }
    }

    return output_dir + "bundle_maps/IIT_bundles"
}

def get_thresholds() {
    return [
        "AC": 3,
        "AF_L": 2,
        "AF_R": 2,
        "AST_L": 5,
        "AST_R": 5,
        "C_L": 3,
        "C_R": 3,
        "CC_ForcepsMajor": 5,
        "CC_ForcepsMinor": 2,
        "CC": 1,
        "CCMid": 4,
        "CST_L": 0,
        "CST_R": 0,
        "F_L_R": 0,
        "FPT_L": 1,
        "FPT_R": 1,
        "ICP_L": 5,
        "ICP_R": 5,
        "IFOF_L": 0,
        "IFOF_R": 0,
        "ILF_L": 5,
        "ILF_R": 2,
        "MCP": 5,
        "MdLF_L": 5,
        "MdLF_R": 5,
        "ML_L": 150,
        "ML_R": 150,
        "OPT_L": 0,
        "OPT_R": 0,
        "OR_L": 5,
        "OR_R": 10,
        "PPT_L": 2,
        "PPT_R": 2,
        "SCP": 50,
        "SLF_L": 10,
        "SLF_R": 5,
        "STT_L": 150,
        "STT_R": 150,
        "UF_L": 0,
        "UF_R": 0,
        "VOF_L": 15,
        "VOF_R": 3
    ]
}

boolean allBundleFilesExist(Map thresholds, File dir) {
    thresholds.every { key, value ->
        new File(dir, "${key}.nii.gz").exists()
    }
}

workflow {
    ATLAS_IIT()
}

workflow ATLAS_IIT {
    main:

    ch_versions = channel.empty()

    if (params.atlas_iit.b0) {
        ch_b0 = channel.fromPath(params.atlas_iit.b0, checkIfExists: true)
    }
    else {
        // Create atlas_iit directory if it doesn't exist
        new File("${workflow.workDir}/atlas_iit/").mkdirs()
        fetch_iit_atlas_b0(
            "https://www.nitrc.org/frs/download.php/11266/IITmean_b0.nii.gz",
            "${workflow.workDir}/atlas_iit/"
        )
        ch_b0 = channel.fromPath("${workflow.workDir}/atlas_iit/IITmean_b0.nii.gz", checkIfExists: true)
    }

    if (params.atlas_iit.bundle_masks_dir) {
        ch_bundle_masks = channel.fromPath(params.atlas_iit.bundle_masks_dir + "/*.nii.gz", checkIfExists: true).collect()
    }
    else {
        def thresholds = get_thresholds()
        def atlas_tdi = fetch_iit_atlas_tdi(
            "https://www.nitrc.org/frs/download.php/11472/IIT_bundles.zip",
            "${workflow.workDir}/atlas_iit/bundles/tdi",
            thresholds
        )

        bundle_maps = channel.fromPath(atlas_tdi + "/*.nii.gz", checkIfExists: true)
        // Pair all bundle maps with their respective thresholds
        ch_bundle_maps_with_thresholds = bundle_maps.map { file ->
            def file_base_name = file.baseName.replace(".nii.gz", "").replace(".nii", "")
            def thr_find = thresholds.find { line -> line.key == file_base_name }?.value
            def thr = thr_find != null ? thr_find : null
            def meta = [ id: file_base_name ]
            return [meta, file, thr]
        }

        IMAGE_MATH(ch_bundle_maps_with_thresholds)

        ch_bundle_masks = IMAGE_MATH.out.image
            .map { _meta, mask -> mask }
            .collect()
    }

    emit:
    b0 = ch_b0
    bundle_masks = ch_bundle_masks
    versions = ch_versions
}

// TODO: THIS WILL BE REPLACED BY THE OFFICIAL MODULE ONCE ITS MERGED
process IMAGE_MATH {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:2.2.1_cpu"

    input:
        tuple val(meta), path(images), val(value) /* optional = null */

    output:
        tuple val(meta), path("*.nii.gz")        , emit: image
        path "versions.yml"                      , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ?: "output"
    def value_ = task.ext.value != null ? task.ext.value : value != null ? value : ""
    def data_type = task.ext.data_type ?: "float32"
    def exclude_background = task.ext.exclude_background ? "--exclude_background" : ""

    def operations = [
        'absolute_value',
        'addition',
        'blur',
        'ceil',
        'closing',
        'concatenate',
        'convert',
        'correlation',
        'difference',
        'dilation',
        'division',
        'erosion',
        'floor',
        'intersection',
        'invert',
        'log_10',
        'log_e',
        'lower_clip',
        'lower_threshold',
        'lower_threshold_eq',
        'lower_threshold_otsu',
        'mean',
        'multiplication',
        'normalize_sum',
        'normalize_max',
        'opening',
        'round',
        'std',
        'subtraction',
        'union',
        'upper_clip',
        'upper_threshold',
        'upper_threshold_eq',
        'upper_threshold_otsu',
    ]

    assert task.ext.operation in operations : "Invalid operation: ${task.ext.operation}. " +
        "Must be one of ${operations}"

    """
    scil_volume_math ${task.ext.operation} $images $value_ \
        ${prefix}${suffix}.nii.gz --data_type $data_type $exclude_background -f

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ?: "output"
    """
    scil_volume_math -h
    touch ${prefix}__${suffix}.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(pip list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}

