defmodule CastorEDC.Explorer do
  @moduledoc """
  A Castor EDC study's data as `Explorer.DataFrame`s.

  Every frame's dtypes come from the study's structure, not from inferring
  them from the data, so a column has the same dtype whatever values it
  happens to hold, and an empty study gives frames with the same columns
  as a full one.

      client = CastorEDC.new(client_id: "...", client_secret: "...")
      {:ok, frame} = CastorEDC.Explorer.data_points(client, study_id)

  Functions return `{:ok, result}`, or `{:error, %CastorEDC.Error{}}` when
  a request fails.
  """

  alias CastorEDC.Explorer.Frame
  alias CastorEDC.Tabular
  alias Explorer.DataFrame

  @typedoc """
  A study's values in the wide format: a frame for its own values, and one
  per repeating data and per survey, keyed by their names (or their IDs,
  when two share a name).
  """
  @type wide :: %{
          study: DataFrame.t(),
          repeating_data: %{String.t() => DataFrame.t()},
          surveys: %{String.t() => DataFrame.t()}
        }

  @sources [:study, :repeating_data, :survey]

  @long [
    {"participant_id", :participant_id, :string},
    {"site_id", :site_id, :string},
    {"source", :source, :string},
    {"instance_id", :instance_id, :string},
    {"parent_id", :parent_id, :string},
    {"field_id", :field_id, :string},
    {"variable_name", :variable_name, :string},
    {"value", :value, :string},
    {"missing", :missing, {:s, 16}},
    {"raw_value", :raw_value, :string},
    {"updated_on", :updated_on, {:naive_datetime, :microsecond}}
  ]

  @doc """
  The values the study collected, from `CastorEDC.Tabular.data_points/3`.

  By default, a single frame with a row per value, holding the study's,
  repeating data's and surveys' values alike:

  | Column | Dtype | |
  | --- | --- | --- |
  | `participant_id`, `site_id` | `:string` | whose value it is |
  | `source` | `:string` | `"study"`, `"repeating_data"` or `"survey"` |
  | `instance_id`, `parent_id` | `:string` | the repeating data or survey instance, and the repeating data or survey; `nil` for the study's values |
  | `field_id`, `variable_name` | `:string` | the field |
  | `value` | `:string` | the decoded value as text: ISO 8601 for dates and times, `;` between checked options |
  | `missing` | `{:s, 16}` | the code of a value marked missing (95 to 99), whose `value` is `nil` |
  | `raw_value` | `:string` | the value as the API sent it |
  | `updated_on` | `{:naive_datetime, :microsecond}` | when it last changed |

  With `format: :wide`, a `t:wide/0` map of frames: one for the study's
  values, with a row per participant, and one for each repeating data and
  survey, with a row per instance. After `participant_id` and `site_id`
  (and `instance_id` for repeating data and surveys) comes a column per
  variable, in the order the study shows them, typed by its field:

  | Field type | Dtype |
  | --- | --- |
  | `numeric`, `slider` | `{:f, 64}` |
  | `year` | `{:s, 64}` |
  | `date` | `:date` |
  | `time` | `:time` |
  | `datetime` | `{:naive_datetime, :microsecond}` |
  | `checkbox` | a `:boolean` column per option, `<variable>_<option value>` |
  | others | `:string`, as text as in the long format |

  Values marked missing and encrypted values are `nil`. With
  `missing_columns: true`, each variable also gets a `<variable>_missing`
  column of `{:s, 16}` holding the code.

  ## Options

    * `:format` - `:long` (the default) or `:wide`
    * `:missing_columns` - add the missing-value columns to wide frames;
      `false` by default
    * `:sources` and `:schema` - as for `CastorEDC.Tabular.data_points/3`
  """
  @spec data_points(CastorEDC.client(), String.t(), keyword()) ::
          {:ok, DataFrame.t() | wide()} | {:error, CastorEDC.Error.t()}
  def data_points(client, study_id, opts \\ []) do
    {missing_columns, opts} = Keyword.pop(opts, :missing_columns, false)

    case Keyword.get(opts, :format, :long) do
      :long -> {:ok, long(client, study_id, opts)}
      :wide -> {:ok, wide(client, study_id, opts, missing_columns)}
      other -> raise ArgumentError, "expected :format to be :long or :wide, got: #{inspect(other)}"
    end
  rescue
    error in CastorEDC.Error -> {:error, error}
  end

  defp long(client, study_id, opts) do
    client
    |> Tabular.data_points(study_id, opts)
    |> Enum.map(&%{&1 | source: Atom.to_string(&1.source)})
    |> Enum.map(&Map.put(&1, :missing, Frame.missing(&1.value)))
    |> Frame.from_rows(@long)
  end

  defp wide(client, study_id, opts, missing_columns) do
    schema = Keyword.get_lazy(opts, :schema, fn -> schema!(client, study_id) end)
    sources = Keyword.get(opts, :sources, @sources)

    rows =
      client
      |> Tabular.data_points(study_id, Keyword.put(opts, :schema, schema))
      |> Enum.group_by(&{&1.source, &1.parent_id})

    frames =
      for {{context, parent_id} = key, columns} <- groups(schema, sources) do
        {context, parent_id, parent_name(columns), frame(context, columns, Map.get(rows, key, []), missing_columns)}
      end

    %{
      study: Enum.find_value(frames, &study_frame/1) || frame(:study, [], [], missing_columns),
      repeating_data: named(frames, :repeating_data),
      surveys: named(frames, :survey)
    }
  end

  defp study_frame({:study, _id, _name, frame}), do: frame
  defp study_frame(_other), do: nil

  # The schema's columns by the frame they belong to.
  defp groups(schema, sources) do
    schema
    |> Map.values()
    |> Enum.filter(&(&1.context in sources))
    |> Enum.group_by(&{&1.context, if(&1.context != :study, do: &1.parent_id)})
  end

  defp schema!(client, study_id) do
    case Tabular.schema(client, study_id) do
      {:ok, schema} -> schema
      {:error, error} -> raise error
    end
  end

  defp parent_name(columns), do: Enum.find_value(columns, & &1.parent_name)

  defp named(frames, context) do
    entries = for {^context, id, name, frame} <- frames, do: {id, name || id, frame}
    shared = entries |> Enum.frequencies_by(&elem(&1, 1)) |> Map.filter(fn {_name, count} -> count > 1 end)

    Map.new(entries, fn {id, name, frame} -> {if(Map.has_key?(shared, name), do: id, else: name), frame} end)
  end

  defp frame(context, columns, rows, missing_columns) do
    fixed =
      [{"participant_id", :participant_id}, {"site_id", :site_id}] ++
        if context == :study, do: [], else: [{"instance_id", :instance_id}]

    variables =
      columns
      |> Enum.sort_by(&{&1.position, variable_name(&1)})
      |> Enum.flat_map(&variable_columns(&1, missing_columns))

    rows = Enum.sort_by(rows, &{&1.participant_id, &1.instance_id})

    Frame.new(
      Enum.map(fixed, fn {name, key} -> {name, :string, Enum.map(rows, &Map.get(&1, key))} end) ++
        Enum.map(variables, fn {name, dtype, read} -> {name, dtype, Enum.map(rows, read)} end)
    )
  end

  # The frame columns of a field: {name, dtype, a function reading the
  # column's value from a wide row}.
  defp variable_columns(column, missing_columns) do
    names = for {name, _value} <- Tabular.wide_cells([column], %{}), do: name
    dtype = dtype(column)
    values = for name <- names, do: {name, dtype, &Frame.cast(Map.get(&1, name), dtype)}

    if missing_columns do
      first = hd(names)
      values ++ [{"#{variable_name(column)}_missing", {:s, 16}, &Frame.missing(Map.get(&1, first))}]
    else
      values
    end
  end

  defp variable_name(%{variable_name: name}) when is_binary(name) and name != "", do: name
  defp variable_name(%{field_id: id}), do: id

  # A checkbox field has a boolean column per option; one without options
  # keeps its list, as text.
  defp dtype(%{field_type: "checkbox", option_group: %{options: [_option | _more]}}), do: :boolean
  defp dtype(%{type: :number}), do: {:f, 64}
  defp dtype(%{type: :integer}), do: {:s, 64}
  defp dtype(%{type: :date}), do: :date
  defp dtype(%{type: :time}), do: :time
  defp dtype(%{type: :naive_datetime}), do: {:naive_datetime, :microsecond}
  defp dtype(_column), do: :string
end
