process HARMONIZATION_CLINICALCOMBAT {
    label 'process_medium'

    container "scilus/clinical_combat:1.0.1"

    input:
    tuple path(ref_site), path(move_site)

    output:
    path("*.model.csv")                , emit: model
    path("*.harmonized.csv.gz")        , emit: harmonizedsite
    path("qc_reports/*")               , emit: bdqc
    path("figures/*")                  , emit: figures
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
    combat_quick $ref_site $move_site $method $bundles_list \
        $limit_age $ignore_sex $ignore_handedness \
        $regul_ref $regul_mov $degree $nu $tau $degree_qc \
        $no_eb

    mkdir -p qc_reports figures
    mv *bhattacharrya.txt qc_reports
    mv *.png figures

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        clinical-ComBAT: \$(uv pip -q -n list | grep clinical-ComBAT | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def method = task.ext.method ?: "clinical"

    // Extract the site and metric name from the input filenames
    // We do this to avoid having file collisions when stubbing
    def stub_ref_site = ref_site.getName().split("\\.")[0]
    def stub_mov_site = move_site.getName().split("\\.")[0]
    def stub_metric = ref_site.getName().split("\\.")[1]

    """
    combat_quick -h

    mkdir -p figures qc_reports
    touch figures/dummy_figure_1.png
    touch figures/dummy_figure_2.png
    touch qc_reports/${stub_ref_site}_${stub_mov_site}.${stub_metric}_report_1.txt
    touch qc_reports/${stub_ref_site}_${stub_mov_site}.${stub_metric}_report_2.txt
    touch ${stub_ref_site}_${stub_mov_site}.${stub_metric}.${method}.model.csv
    touch ${stub_ref_site}_${stub_mov_site}.${stub_metric}.${method}.harmonized.csv.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        clinical-ComBAT: \$(uv pip -q -n list | grep clinical-ComBAT | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
