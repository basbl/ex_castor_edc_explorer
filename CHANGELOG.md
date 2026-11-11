# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- `CastorEDC.Explorer.domains/3` reads a participant data export grouped by domain into a frame per domain, with a row per participant per visit, repeating data instance or survey, typed by the domain's variable list, and the codes of missing values and the options' names in columns of their own when asked.
  It takes `from:` as `participant_data/3` does, which now refuses a grouped export.
- `from:` on `CastorEDC.Explorer.participant_data/3` reads an export already made instead of running one: the `CastorEDC.Export` struct a download returned (in memory, saved or unzipped), or the path to its zip or the directory it was unzipped into.
- `labels: true` on `CastorEDC.Explorer.data_points/3` gives the names of the chosen options, which the user saw, next to their values: a `label` column in the long frame, and the names instead of the values in the wide frames' radio and dropdown columns.
- `CastorEDC.Explorer.survey_package_instances/2`, `repeating_data_instances/2` and `queries/2` give those resources as frames, a row each, with fixed dtypes.
  A survey package instance's `parent_type` is named (`"visit"` or `"repeating_data_instance"`) instead of the API's code, and a query's `remarks` counts its remarks.
- `CastorEDC.Explorer.from_structs/1` makes a frame from any of the client's results, a list, page or stream of structs, for resources without a function of their own, such as countries or visits.
  Its dtypes are inferred from the values, and nested objects and lists are left out.
- A Livebook, `notebook/charts.livemd`, that draws a study's standard charts with VegaLite: enrolment per site, progress, completeness per form, missing data by reason, data entry per week, survey packages and queries by status, and any variable's spread per site or its options' counts.

### Changed

- Builds on ex_castor_edc 1.0 (`~> 1.0`) instead of its release candidate.

### Fixed

- `CastorEDC.Explorer.participant_data/3` reads the export's -95 to -99 as missing values in every field but dates and checkboxes, not only in numeric and year fields.
  A missing datetime was logged as unreadable and lost its code, and a missing radio, dropdown or text value came through as the text `"-98"`; they're now nulls, and with `missing_columns: true` those fields get a `<variable>_missing` column too.

## [0.1.0] - 2026-10-15

### Added

- `CastorEDC.Explorer.data_points/3` gives the values a study collected as a frame with a row per value, or with `format: :wide` as a frame per study, repeating data and survey with a column per variable, typed by its field.
  Values marked missing are null, with their codes in a column of their own.
- `CastorEDC.Explorer.participants/2`, `fields/2`, `sites/2` and `option_groups/2` give those resources as frames, a row each (a row per option for option groups), with fixed dtypes; times are in UTC.
- `CastorEDC.Explorer.participant_data/3` loads a participant data export (CSV) into a frame per study, repeating data and survey, typed by the export's own variable lists, with checkbox columns named after their options' values and the export's codes for missing values turned into nulls (and, if asked, codes in columns of their own).
  It takes a few requests however big the study is.
- A Livebook, `notebook/analysis.livemd`, that loads a study into frames and takes a first look at it.

[0.1.0]: https://hex.pm/packages/ex_castor_edc_explorer/0.1.0
