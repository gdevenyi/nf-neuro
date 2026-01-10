include { HARMONIZATION_CLINICALCOMBAT } from '../../../modules/nf-neuro/harmonization/clinicalcombat/main'

workflow HARMONIZATION {

    take:
    ch_moving_site
    ch_reference_site

    main:
    ch_versions = Channel.empty()

    HARMONIZATION_CLINICALCOMBAT(

    )
    ch_versions = ch_versions.mix(SAMTOOLS_SORT.out.versions.first())

    emit:
    versions = ch_versions                     // channel: [ versions.yml ]
}

def checkColumnOrder(tabular_file, expected_columns) {
    def header = tabular_file.readLines()[0]
    def columns = header.split("\t") as List
    return columns == expected_columns

}
