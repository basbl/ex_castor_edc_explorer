# CastorEDC.Explorer

[![Package](https://img.shields.io/hexpm/v/ex_castor_edc_explorer.svg)](https://hex.pm/packages/ex_castor_edc_explorer) [![Documentation](http://img.shields.io/badge/hex.pm-docs-green.svg?style=flat)](https://hexdocs.pm/ex_castor_edc_explorer) ![CI](https://github.com/basbl/ex_castor_edc_explorer/actions/workflows/ci.yml/badge.svg)

Castor EDC study data as [Explorer](https://hexdocs.pm/explorer) dataframes.

It builds on [ex_castor_edc](https://hexdocs.pm/ex_castor_edc), and takes every frame's dtypes from the study's structure instead of inferring them from the data.

## Installation

```elixir
def deps do
  [
    {:ex_castor_edc_explorer, "~> 0.1.0"}
  ]
end
```

## Usage

```elixir
client = CastorEDC.new(client_id: "...", client_secret: "...")

# A row per value: the study's, repeating data's and surveys' values alike.
{:ok, values} = CastorEDC.Explorer.data_points(client, study_id)

# With the names of the chosen options, as the user saw them, next to their values.
{:ok, values} = CastorEDC.Explorer.data_points(client, study_id, labels: true)

# A frame per study, repeating data and survey, with a column per variable.
{:ok, %{study: study, repeating_data: repeating_data, surveys: surveys}} =
  CastorEDC.Explorer.data_points(client, study_id, format: :wide)

# The same frames from a batch export: a few requests however big the study.
{:ok, %{study: study, repeating_data: repeating_data, surveys: surveys}} =
  CastorEDC.Explorer.participant_data(client, study_id)

# Or from an export already downloaded: the struct, or the path to its zip or directory.
{:ok, frames} = CastorEDC.Explorer.participant_data(client, study_id, from: "exports/study.zip")

# A frame per domain, from the export grouped by the study's domains.
{:ok, %{"DM" => demographics}} = CastorEDC.Explorer.domains(client, study_id, labels: true)

# The study's participants, fields, sites and options.
{:ok, participants} = CastorEDC.Explorer.participants(client, study_id)
{:ok, fields} = CastorEDC.Explorer.fields(client, study_id)
{:ok, sites} = CastorEDC.Explorer.sites(client, study_id)
{:ok, options} = CastorEDC.Explorer.option_groups(client, study_id)

# The survey packages sent, the repeating data instances made, and the queries raised.
{:ok, packages} = CastorEDC.Explorer.survey_package_instances(client, study_id)
{:ok, instances} = CastorEDC.Explorer.repeating_data_instances(client, study_id)
{:ok, queries} = CastorEDC.Explorer.queries(client, study_id)

# Anything else the client returns, from a list, page or stream of its structs.
countries = client |> CastorEDC.Countries.list_countries!() |> CastorEDC.Explorer.from_structs()
```

## Contributing

See [CONTRIBUTING.md](https://github.com/basbl/ex_castor_edc_explorer/blob/main/CONTRIBUTING.md).

## License

MIT; see [LICENSE.md](https://github.com/basbl/ex_castor_edc_explorer/blob/main/LICENSE.md).
