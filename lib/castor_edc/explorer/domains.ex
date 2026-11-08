defmodule CastorEDC.Explorer.Domains do
  @moduledoc false
  # Reads the CSV files of a grouped participant data export, which has a
  # file per domain, typed by the domain's own variable list.

  alias CastorEDC.Explorer.Frame
  alias Explorer.DataFrame
  alias Explorer.Series

  require Logger

  # Metadata columns whose variable list type doesn't suit them: an ID that
  # isn't a number to compute with, and a visit's number.
  @metadata %{
    "randomization_id" => {"randomization_id", :string},
    "visit_number" => {"visit_number", :integer},
    "participant_creation_date" => {"created_on", :datetime},
    "randomized_on" => {"randomized_on", :datetime}
  }

  @missing_codes Map.new(95..99, &{"-#{&1}", &1})

  @doc false
  # Whether the files, as {name, contents}, are a grouped export's.
  @spec grouped?([{String.t(), binary()}]) :: boolean()
  def grouped?(files), do: Enum.any?(files, fn {name, _contents} -> Path.basename(name) == "domain_mapping.csv" end)

  @doc false
  # A frame per domain, keyed by its abbreviation, with the missing codes'
  # and the options' names columns when asked.
  @spec read([{String.t(), binary()}], boolean(), boolean()) :: %{String.t() => DataFrame.t()}
  def read(files, missing_columns, labels) do
    files = Map.new(files, fn {name, contents} -> {Path.basename(name), strip_bom(contents)} end)

    for {name, contents} <- files, String.ends_with?(name, "_variablelist.csv"), into: %{} do
      domain = String.replace_suffix(name, "_variablelist.csv", "")
      variables = variables(contents)

      frame =
        case files["#{domain}.csv"] do
          nil -> Frame.new([])
          data -> data |> load() |> type(variables, missing_columns, labels)
        end

      {domain, frame}
    end
  end

  defp strip_bom("﻿" <> contents), do: contents
  defp strip_bom(contents), do: contents

  # Every column as a string, so nothing is inferred.
  defp load(contents), do: DataFrame.load_csv!(contents, delimiter: ";", infer_schema_length: 0)

  # Each column's kind, from the variable list: {name in the frame, kind},
  # with a checkbox's columns named after their options' values and the
  # missing-code and name columns marked as such.
  defp variables(contents) do
    rows = contents |> load() |> DataFrame.to_rows()
    names = MapSet.new(rows, & &1["Domain variable name"])

    Map.new(rows, fn row ->
      column = row["Domain variable name"]
      {column, kind(row, column, names)}
    end)
  end

  defp kind(%{"Domain abbreviation" => "Metadata"} = row, column, _names) do
    {name, kind} = Map.get(@metadata, column, {column, metadata_kind(row["Field type"])})
    {:metadata, name, kind}
  end

  defp kind(row, column, names) do
    base = String.replace_suffix(column, "_U", "")
    named = String.replace_suffix(column, "_N", "")

    cond do
      String.ends_with?(column, "_U") and MapSet.member?(names, base) -> {:missing, base}
      String.ends_with?(column, "_N") and MapSet.member?(names, named) -> {:label, named}
      row["Field type"] == "checkbox" -> {checkbox_name(row, column), :boolean}
      true -> {column, value_kind(row["Field type"], row["SAS field type"])}
    end
  end

  defp metadata_kind("datetime"), do: :datetime
  defp metadata_kind(_type), do: :string

  defp value_kind(_type, "YYMMDD10"), do: :date
  defp value_kind(type, _sas) when type in ["numeric", "slider", "numberdate"], do: :number
  defp value_kind("year", _sas), do: :integer
  defp value_kind("date", _sas), do: :date
  defp value_kind("time", _sas), do: :time
  defp value_kind("datetime", _sas), do: :datetime
  defp value_kind(_type, _sas), do: :string

  # A checkbox's columns are named after its options' names, cut short;
  # the frame names them `<variable>_<option value>`, as the data points
  # have them. The variable list names the variable only in its info.
  defp checkbox_name(row, column) do
    case {Regex.run(~r/related to the (\S+) domain variable/, row["Variable info"] || ""), row["Option value"]} do
      {[_match, variable], value} when is_binary(value) -> "#{variable}_#{value}"
      _other -> column
    end
  end

  defp type(frame, variables, missing_columns, labels) do
    headers = DataFrame.names(frame)
    codes = for header <- headers, {:missing, base} <- [variables[header]], into: %{}, do: {base, header}

    headers
    |> Enum.flat_map(&columns(&1, frame, variables, codes, {missing_columns, labels}))
    |> Enum.uniq_by(&elem(&1, 0))
    |> Frame.new()
  end

  defp columns(header, frame, variables, codes, {missing_columns, labels}) do
    values = frame[header] |> Series.to_list() |> Enum.map(&blank_to_nil/1)

    case Map.get(variables, header, {:metadata, header, :string}) do
      {:missing, _base} ->
        []

      {:metadata, name, kind} ->
        [{name, dtype(kind), Enum.map(values, &parse(&1, kind, name))}]

      {:label, base} ->
        if labels, do: [{base <> "_label", :string, values}], else: []

      {name, :boolean} ->
        [{name, :boolean, Enum.map(values, &(&1 && &1 != "0"))}] ++
          missing_column(checkbox_variable(name), header, frame, codes, missing_columns)

      {name, kind} ->
        [{name, dtype(kind), Enum.map(values, &parse(missing_free(&1, kind), kind, name))}] ++
          missing_column(name, header, frame, codes, missing_columns)
    end
  end

  # The missing codes of a variable, from its `_U` column, or from values
  # written as codes in its own column.
  defp missing_column(_name, _header, _frame, _codes, false), do: []

  defp missing_column(name, header, frame, codes, true) do
    source = Map.get(codes, header, header)
    codes = frame[source] |> Series.to_list() |> Enum.map(&@missing_codes[&1])
    [{name <> "_missing", {:s, 16}, codes}]
  end

  defp checkbox_variable(name), do: name |> String.split("_") |> Enum.drop(-1) |> Enum.join("_")

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp missing_free(value, kind) when kind != :date, do: if(@missing_codes[value], do: nil, else: value)
  defp missing_free(value, _kind), do: value

  defp dtype(:number), do: {:f, 64}
  defp dtype(:integer), do: {:s, 64}
  defp dtype(:date), do: :date
  defp dtype(:time), do: :time
  defp dtype(:datetime), do: {:naive_datetime, :microsecond}
  defp dtype(:string), do: :string

  defp parse(nil, _kind, _column), do: nil
  defp parse(value, :string, _column), do: value

  defp parse(value, kind, column) do
    case read_value(value, kind) do
      {:ok, parsed} ->
        parsed

      :error ->
        Logger.warning("CastorEDC.Explorer couldn't read #{inspect(value)} in column #{column} as a #{kind}")
        nil
    end
  end

  defp read_value(value, :number) do
    case Float.parse(value) do
      {number, ""} -> {:ok, number}
      _other -> :error
    end
  end

  defp read_value(value, :integer) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _other -> :error
    end
  end

  defp read_value(value, :date), do: value |> Date.from_iso8601() |> ok()
  defp read_value(<<_h::binary-2, ":", _m::binary-2>> = value, :time), do: read_value(value <> ":00", :time)
  defp read_value(value, :time), do: value |> Time.from_iso8601() |> ok()

  defp read_value(value, :datetime) do
    case String.split(value, " ", parts: 2) do
      [date, time] ->
        with {:ok, date} <- read_value(date, :date),
             {:ok, time} <- read_value(time, :time),
             do: {:ok, NaiveDateTime.new!(date, time)}

      _other ->
        :error
    end
  end

  defp ok({:ok, value}), do: {:ok, value}
  defp ok({:error, _reason}), do: :error
end
