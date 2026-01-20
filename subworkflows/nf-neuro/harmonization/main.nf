include { HARMONIZATION_CLINICALCOMBAT } from '../../../modules/nf-neuro/harmonization/clinicalcombat/main'
include { HARMONIZATION_FORMATSTATS as FORMAT_INPUT_MOVING } from '../../../modules/nf-neuro/harmonization/formatstats/main'
include { HARMONIZATION_FORMATSTATS as FORMAT_INPUT_REFERENCE } from '../../../modules/nf-neuro/harmonization/formatstats/main'
include { HARMONIZATION_FORMATSTATS as FORMAT_OUTPUT } from '../../../modules/nf-neuro/harmonization/formatstats/main'

workflow HARMONIZATION {

    take:
    ch_reference_site
    ch_moving_site

    main:
    ch_versions = channel.empty()

    if (!ch_moving_site || !ch_reference_site) {
        error "HARMONIZATION workflow requires both 'ch_moving_site' and 'ch_reference_site' inputs to be provided."
    }

    // Format the input stats files
    FORMAT_INPUT_REFERENCE(ch_reference_site)
    ch_versions = ch_versions.mix(FORMAT_INPUT_REFERENCE.out.versions)
    ch_reference_metrics = FORMAT_INPUT_REFERENCE.out.raw_files
        .flatten()
        .map{ file ->
            // Extract the metric name from the filename which
            // is in the format: <site>.<metric>.*
            [[metric: file.getName().split("\\.")[1]], file]
        }

    FORMAT_INPUT_MOVING(ch_moving_site)
    ch_versions = ch_versions.mix(FORMAT_INPUT_MOVING.out.versions)
    ch_moving_metrics = FORMAT_INPUT_MOVING.out.raw_files
        .flatten()
        .map{ file ->
            // Extract the metric name from the filename which
            // is in the format: <site>.<metric>.*
            [[metric: file.getName().split("\\.")[1]], file]
        }

    // Group moving and reference metrics by metric name
    ch_grouped_metrics = ch_moving_metrics
        .join(ch_reference_metrics)
        .map{ _meta, moving_entry, reference_entry ->
            [ reference_entry, moving_entry ]
        }

    // Run the harmonization
    HARMONIZATION_CLINICALCOMBAT(ch_grouped_metrics)
    ch_versions = ch_versions.mix(HARMONIZATION_CLINICALCOMBAT.out.versions.first())

    // Group by site
    ch_harmonized_files = HARMONIZATION_CLINICALCOMBAT.out.harmonizedsite
        .map{ file ->
            // Extract the metric name from the filename which
            // is in the format: <site>.<metric>.*
            [[site: file.getName().split("\\.")[0]], file]
        }
        .groupTuple()
        .map { _site, files -> files }

    // Combine/format the output harmonized metrics into a MultiQC friendly TSV format
    FORMAT_OUTPUT(ch_harmonized_files)
    ch_versions = ch_versions.mix(FORMAT_OUTPUT.out.versions)

    emit:
    harmonized_metrics   = FORMAT_OUTPUT.out.harmonized_files
    figures              = HARMONIZATION_CLINICALCOMBAT.out.figures
    model                = HARMONIZATION_CLINICALCOMBAT.out.model
    qc_reports           = HARMONIZATION_CLINICALCOMBAT.out.bdqc

    versions = ch_versions                     // channel: [ versions.yml ]
}
