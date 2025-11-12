process HARMONIZATION_CLINICALCOMBAT {
    tag "$meta.id"
    label 'process_medium'

    container "scilus/clinical_combat:1.0.0"

    input:
    tuple path(ref_site), path(move_site)

    output:
    path("*.model.csv")                , emit: model
    path("*.csv.gz")                   , emit: harmonizedsite
    path("*.raw.bhattacharrya.txt")    , emit: rawbd
    path("*.bhattacharrya.txt")        , emit: harmbd
    path("AgeCurve*raw*png")           , emit: rawcurve
    path("AgeCurve*png")               , emit: harmcurve
    path("DataModels*png")             , emit: modelcurve
    path "versions.yml"                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def method = task.ext.method ? "--method " + task.ext.method : ""
    def bundles_list = task.ext.bundles ? "--bundles " + task.ext.bundles : "--bundles all"
    def regul_ref = task.ext.regul_ref ? "--regul_ref " + task.ext.regul_ref : ""
    def regul_mov = task.ext.regul_mov ? "--regul_mov " + task.ext.regul_mov : ""
    def degree = task.ext.degree ? "--degree " + task.ext.degree : ""
    def nu = task.ext.nu ? "--nu " + task.ext.nu : ""
    def tau = task.ext.tau ? "--tau " + task.ext.tau : ""
    def degree_qc = task.ext.degree_qc ? "--degree_qc " + task.ext.degree_qc : ""

    def limit_age = task.ext.limit_age_range ? "--limit_age_range " : ""
    def ignore_sex = task.ext.ignore_sex ? "--ignore_sex " : ""
    def ignore_handedness = task.ext.ignore_handedness ? "--ignore_handedness " : ""
    def no_eb = task.ext.no_empiral_bayes ? "--no_empiral_bayes " : ""

    """
    combat_quick_fit $ref_site $move_site $method $bundles_list \
        $limit_age $ignore_sex $ignore_handedness \
        $regul_ref $regul_mov $degree $nu $tau $degree_qc \
        $no_eb


    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        clinical-ComBAT: \$(uv pip -q -n list | grep clinical-ComBAT | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def smethod = task.ext.method ?: "${task.ext.method}"
    """
    combat_quick_fit -h

    touch ref_mov.metric.${smethod}.model.csv
    touch ref_mov.metric.${smethod}.csv.gz
    touch ref_mov.metric.raw.bhattacharrya.txt
    touch ref_mov.metric.${smethod}.bhattacharrya.txt
    touch AgeCurve_ref-mov_raw_metric_bundle.png
    touch AgeCurve_ref-mov_${smethod}_metric_bundle.png
    touch DataModels_ref-mov_${smethod}_metric_bundle.png

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        clinical-ComBAT: \$(uv pip -q -n list | grep clinical-ComBAT | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
