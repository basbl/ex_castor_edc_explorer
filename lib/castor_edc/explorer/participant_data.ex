defmodule CastorEDC.Explorer.ParticipantData do
  @moduledoc false
  # Reads the CSV files of a participant data export into frames, typed by
  # the export's own variable lists.

  alias CastorEDC.Explorer.Frame
  alias Explorer.DataFrame
  alias Explorer.Series

  require Logger

  @variable_lists ~w(study_variablelist.csv report_variablelist.csv survey_variablelist.csv)

  # The columns before the variables, by their header: their name in the
  # frame, and how to read them.
  @fixed %{
    "Participant Id" => {"participant_id", :string},
    "Castor Participant ID" => {"participant_id", :string},
    "Participant Status" => {"participant_status", :string},
    "Castor Participant Status" => {"participant_status", :string},
    "Site Abbreviation" => {"site_abbreviation", :string},
    "Participant Creation Date" => {"created_on", :timestamp},
    "Repeating Data Creation Date" => {"created_on", :timestamp},
    "Repeating data Name Custom" => {"instance_name", :string},
    "Repeating data Parent" => {"parent", :string},
    "Survey Instance Id" => {"instance_id", :string},
    "Survey Creation Date" => {"created_on", :timestamp},
    "Survey Sent Date" => {"sent_on", :timestamp},
    "Survey Progress" => {"progress", :integer},
    "Survey Completed On" => {"completed_on", :timestamp},
    "Survey Parent" => {"parent", :string},
    "Survey Package Name" => {"survey_package_name", :string},
    "Survey Package Id" => {"survey_package_id", :string}
  }

  @missing_numbers Map.new(95..99, &{"-#{&1}", &1})
  @missing_dates Map.new(95..99, &{"01-01-29#{&1}", &1})

  @doc false
  # The frames of the export's files, given as {name, contents}, with the
  # names of the study's repeating data and surveys.
  @spec read([{String.t(), binary()}], [String.t()], [String.t()], boolean()) :: CastorEDC.Explorer.wide()
  def read(files, repeating_data_names, survey_names, missing_columns) do
    files = Map.new(files, fn {name, contents} -> {Path.basename(name), strip_bom(contents)} end)
    variables = variables(files)

    frames =
      for {name, contents} <- files,
          name not in ["field_options.csv" | @variable_lists],
          String.ends_with?(name, ".csv") do
        frame = contents |> load() |> type(variables, missing_columns)
        {source(frame), name, frame}
      end

    {study_file, study} =
      Enum.find_value(frames, {nil, Frame.new([])}, fn {source, file, frame} -> if source == :study, do: {file, frame} end)

    prefix = if study_file, do: base(study_file) <> "_", else: ""

    %{
      study: study,
      repeating_data: named(frames, :repeating_data, repeating_data_names, prefix),
      surveys: named(frames, :survey, survey_names, prefix)
    }
  end

  defp strip_bom("﻿" <> contents), do: contents
  defp strip_bom(contents), do: contents

  # Every column as a string, so nothing is inferred.
  defp load(contents), do: DataFrame.load_csv!(contents, delimiter: ";", infer_schema_length: 0)

  defp source(frame) do
    names = DataFrame.names(frame)

    cond do
      "instance_id" in names -> :survey
      "instance_name" in names -> :repeating_data
      true -> :study
    end
  end

  # Files are named <study>_<repeating data or survey>_export_<date>.csv,
  # with the name's spaces as underscores and some punctuation dropped. A
  # file that matches none of the names keeps the part of its own.
  defp named(frames, source, names, prefix) do
    for {^source, file, frame} <- frames, into: %{} do
      base = base(file)
      key = normalize(base)

      name =
        names
        |> Enum.filter(&String.ends_with?(key, normalize(&1)))
        |> Enum.max_by(&String.length/1, fn -> String.replace_prefix(base, prefix, "") end)

      {name, frame}
    end
  end

  defp base(file), do: String.replace(file, ~r/_export_\d+\.csv$/, "")

  defp normalize(name), do: name |> String.downcase() |> String.replace(~r/[^\p{L}\p{N}]/u, "")

  # Each variable's original field type and options, from the variable
  # lists and field_options.csv.
  defp variables(files) do
    options =
      case files do
        %{"field_options.csv" => contents} ->
          contents
          |> rows()
          |> Enum.group_by(& &1["Option group name"], &{&1["Option name"], &1["Option value"]})

        _none ->
          %{}
      end

    for list <- @variable_lists, contents = files[list], row <- rows(contents), into: %{} do
      # A checkbox has a row per option, as `<variable>#<option name>`.
      variable = row["Variable name"] |> String.split("#", parts: 2) |> hd()
      {variable, %{type: row["Original field type"], options: Map.get(options, row["Optiongroup name"], [])}}
    end
  end

  defp rows(contents) do
    contents |> load() |> DataFrame.to_rows()
  end

  defp type(frame, variables, missing_columns) do
    frame
    |> DataFrame.names()
    |> Enum.flat_map(&columns(&1, frame[&1], variables, missing_columns))
    |> Frame.new()
  end

  defp columns(header, series, variables, missing_columns) do
    values = series |> Series.to_list() |> Enum.map(&blank_to_nil/1)

    case {@fixed[header], String.split(header, "#", parts: 2)} do
      {{name, kind}, _parts} ->
        [{name, dtype(kind), Enum.map(values, &parse(&1, kind, name))}]

      {nil, [variable, option]} ->
        [{checkbox_name(variable, option, variables), :boolean, Enum.map(values, &(&1 && &1 != "0"))}]

      {nil, [variable]} ->
        kind = kind(variables[variable])
        column = {variable, dtype(kind), Enum.map(values, &parse(missing_free(&1, kind), kind, variable))}

        if missing_columns and kind != :string,
          do: [column, {variable <> "_missing", {:s, 16}, Enum.map(values, &missing(&1, kind))}],
          else: [column]
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # A checkbox's columns are named after its options' names; the frame
  # names them after their values, as the data points have them.
  defp checkbox_name(variable, option, variables) do
    options = get_in(variables, [variable, :options]) || []

    case List.keyfind(options, option, 0) do
      {_name, value} -> "#{variable}_#{value}"
      nil -> "#{variable}_#{option}"
    end
  end

  defp kind(%{type: type}) when type in ["numeric", "slider"], do: :number
  defp kind(%{type: "year"}), do: :integer
  defp kind(%{type: "date"}), do: :date
  defp kind(%{type: "datetime"}), do: :datetime
  defp kind(%{type: "time"}), do: :time
  defp kind(_other), do: :string

  defp dtype(:number), do: {:f, 64}
  defp dtype(:integer), do: {:s, 64}
  defp dtype(:date), do: :date
  defp dtype(:time), do: :time
  defp dtype(kind) when kind in [:datetime, :timestamp], do: {:naive_datetime, :microsecond}
  defp dtype(:string), do: :string

  # Values marked missing are written as -95 to -99 in numbers and as the
  # dates 1 January 2995 to 2999.
  defp missing(nil, _kind), do: nil
  defp missing(value, kind) when kind in [:number, :integer], do: @missing_numbers[value]

  defp missing(value, kind) when kind in [:date, :datetime],
    do: @missing_dates[value |> String.split(" ", parts: 2) |> hd()]

  defp missing(_value, _kind), do: nil

  defp missing_free(value, kind), do: if(missing(value, kind), do: nil, else: value)

  defp parse(nil, _kind, _column), do: nil
  defp parse(value, :string, _column), do: value

  defp parse(value, kind, column) do
    case read(value, kind) do
      {:ok, parsed} ->
        parsed

      :error ->
        Logger.warning("CastorEDC.Explorer couldn't read #{inspect(value)} in column #{column} as a #{kind}")
        nil
    end
  end

  defp read(value, :number) do
    case Float.parse(value) do
      {number, ""} -> {:ok, number}
      _other -> :error
    end
  end

  defp read(value, :integer) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _other -> :error
    end
  end

  defp read(<<day::binary-2, "-", month::binary-2, "-", year::binary-4>>, :date),
    do: "#{year}-#{month}-#{day}" |> Date.from_iso8601() |> ok()

  defp read(value, :time),
    do:
      (
        if_result = if(byte_size(value) == 5, do: value <> ":00", else: value)
        if_result |> Time.from_iso8601() |> ok()
      )

  defp read(value, kind) when kind in [:datetime, :timestamp] do
    with [date, time] <- String.split(value, " ", parts: 2),
         {:ok, date} <- read(date, :date),
         {:ok, time} <- read(time, :time) do
      {:ok, NaiveDateTime.new!(date, time)}
    else
      _other -> :error
    end
  end

  defp read(_value, _kind), do: :error

  defp ok({:ok, value}), do: {:ok, value}
  defp ok({:error, _reason}), do: :error
end
