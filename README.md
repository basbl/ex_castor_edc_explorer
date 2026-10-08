# CastorEDC.Explorer

Castor EDC study data as [Explorer](https://hexdocs.pm/explorer) dataframes.

It builds on [ex_castor_edc](https://github.com/basbl/ex_castor_edc), and takes every frame's dtypes from the study's structure instead of inferring them from the data.

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

# A frame per study, repeating data and survey, with a column per variable.
{:ok, %{study: study, repeating_data: repeating_data, surveys: surveys}} =
  CastorEDC.Explorer.data_points(client, study_id, format: :wide)

# The same frames from a batch export: a few requests however big the study.
{:ok, %{study: study, repeating_data: repeating_data, surveys: surveys}} =
  CastorEDC.Explorer.participant_data(client, study_id)

# The study's participants, fields, sites and options.
{:ok, participants} = CastorEDC.Explorer.participants(client, study_id)
{:ok, fields} = CastorEDC.Explorer.fields(client, study_id)
{:ok, sites} = CastorEDC.Explorer.sites(client, study_id)
{:ok, options} = CastorEDC.Explorer.option_groups(client, study_id)
```
