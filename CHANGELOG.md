# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- `CastorEDC.Explorer.data_points/3` gives the values a study collected as a frame with a row per value, or with `format: :wide` as a frame per study, repeating data and survey with a column per variable, typed by its field. Values marked missing are null, with their codes in a column of their own.
- `CastorEDC.Explorer.participants/2`, `fields/2`, `sites/2` and `option_groups/2` give those resources as frames, a row each (a row per option for option groups), with fixed dtypes; times are in UTC.
- `CastorEDC.Explorer.participant_data/3` loads a participant data export (CSV) into a frame per study, repeating data and survey, typed by the export's own variable lists, with checkbox columns named after their options' values and the export's codes for missing values turned into nulls (and, if asked, codes in columns of their own). It takes a few requests however big the study is.
