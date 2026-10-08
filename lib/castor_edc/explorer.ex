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
  alias CastorEDC.Explorer.ParticipantData
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

  @datetime {:datetime, :microsecond, "Etc/UTC"}

  @participants [
    {"participant_id", :participant_id, :string},
    {"site_id", :site_id, :string},
    {"site_name", :site_name, :string},
    {"status", :status, :string},
    {"participant_status", :participant_status, :string},
    {"progress", :progress, {:f, 64}},
    {"locked", :locked, :boolean},
    {"archived", :archived, :boolean},
    {"archived_reason", :archived_reason, :string},
    {"randomization_group", :randomization_group, {:s, 64}},
    {"randomization_group_name", :randomization_group_name, :string},
    {"randomized_id", :randomized_id, :string},
    {"randomized_on", :randomized_on, @datetime},
    {"created_by", :created_by, :string},
    {"created_on", :created_on, @datetime},
    {"updated_by", :updated_by, :string},
    {"updated_on", :updated_on, @datetime}
  ]

  @fields [
    {"field_id", :field_id, :string},
    {"variable_name", :variable_name, :string},
    {"label", :label, :string},
    {"field_type", :field_type, :string},
    {"value_type", :value_type, :string},
    {"context", :context, :string},
    {"parent_id", :parent_id, :string},
    {"parent_name", :parent_name, :string},
    {"form_id", :form_id, :string},
    {"form_name", :form_name, :string},
    {"field_number", :field_number, {:s, 64}},
    {"option_group_id", :option_group_id, :string},
    {"required", :required, :boolean},
    {"hidden", :hidden, :boolean},
    {"units", :units, :string},
    {"min", :field_min, {:f, 64}},
    {"max", :field_max, {:f, 64}}
  ]

  @sites [
    {"site_id", :id, :string},
    {"name", :name, :string},
    {"abbreviation", :abbreviation, :string},
    {"code", :code, :string},
    {"country_id", :country_id, {:s, 64}},
    {"order", :order, {:s, 64}},
    {"deleted", :deleted, :boolean}
  ]

  @option_groups [
    {"option_group_id", :option_group_id, :string},
    {"option_group_name", :option_group_name, :string},
    {"value", :value, :string},
    {"name", :name, :string},
    {"order", :order, {:s, 64}}
  ]

  @doc """
  The study's participants, a row each.

  Columns: `participant_id`, `site_id` and `site_name`, `status`,
  `participant_status` (the name of the study's own status, if it has
  them), `progress` (`{:f, 64}`, a percentage), `locked` and `archived`
  (`:boolean`), `archived_reason`, `randomization_group` (`{:s, 64}`),
  `randomization_group_name`, `randomized_id`, `randomized_on`,
  `created_by`, `created_on`, `updated_by` and `updated_on`. Dates and
  times are `{:datetime, :microsecond, "Etc/UTC"}`, the rest `:string`.
  """
  @spec participants(CastorEDC.client(), String.t()) :: {:ok, DataFrame.t()} | {:error, CastorEDC.Error.t()}
  def participants(client, study_id) do
    resource(@participants, fn ->
      for participant <- CastorEDC.Participants.stream_participants(client, study_id) do
        Map.merge(Map.from_struct(participant), %{
          site_id: participant.site && participant.site.id,
          site_name: participant.site && participant.site.name,
          participant_status: participant.participant_status && participant.participant_status.name
        })
      end
    end)
  end

  @doc """
  The study's fields that hold values, a row each, in the order the study
  shows them, from `CastorEDC.Tabular.schema/2`.

  Columns: `field_id`, `variable_name`, `label`, `field_type`,
  `value_type` (as `CastorEDC.Tabular.value_type/1` gives it, such as
  `"number"` or `"list(string)"`), `context` (`"study"`,
  `"repeating_data"` or `"survey"`), `parent_id` and `parent_name` (the
  visit, repeating data or survey), `form_id`, `form_name`,
  `field_number` (`{:s, 64}`), `option_group_id`, `required` and `hidden`
  (`:boolean`), `units`, and `min` and `max` (`{:f, 64}`).

  Join `option_group_id` with `option_groups/2` for the options.
  """
  @spec fields(CastorEDC.client(), String.t()) :: {:ok, DataFrame.t()} | {:error, CastorEDC.Error.t()}
  def fields(client, study_id) do
    resource(@fields, fn ->
      for column <- client |> schema!(study_id) |> Map.values() |> Enum.sort_by(& &1.position) do
        Map.merge(column, %{
          value_type: value_type(column.type),
          context: column.context && Atom.to_string(column.context),
          field_number: column.field.field_number,
          option_group_id: column.option_group && column.option_group.id,
          required: flag(column.field.field_required),
          hidden: flag(column.field.field_hidden),
          units: column.field.field_units,
          field_min: column.field.field_min,
          field_max: column.field.field_max
        })
      end
    end)
  end

  @doc """
  The study's sites, a row each.

  Columns: `site_id`, `name`, `abbreviation`, `code`, `country_id` and
  `order` (`{:s, 64}`) and `deleted` (`:boolean`).
  """
  @spec sites(CastorEDC.client(), String.t()) :: {:ok, DataFrame.t()} | {:error, CastorEDC.Error.t()}
  def sites(client, study_id) do
    resource(@sites, fn -> CastorEDC.Sites.stream_sites(client, study_id) end)
  end

  @doc """
  The options of the study's option groups, a row per option.

  Columns: `option_group_id`, `option_group_name`, `value` (what a data
  point stores), `name` (what the user saw) and `order` (`{:s, 64}`, the
  option's place in its group).
  """
  @spec option_groups(CastorEDC.client(), String.t()) :: {:ok, DataFrame.t()} | {:error, CastorEDC.Error.t()}
  def option_groups(client, study_id) do
    resource(@option_groups, fn ->
      for group <- CastorEDC.OptionGroups.stream_option_groups(client, study_id), option <- group.options || [] do
        %{
          option_group_id: group.id,
          option_group_name: group.name,
          value: option.value,
          name: option.name,
          order: option.group_order
        }
      end
    end)
  end

  @doc """
  The study's data from a participant data export, as a `t:wide/0` map of
  frames: one for the study's values, and one per repeating data and per
  survey.

  It runs `CastorEDC.Export.participant_data/3` in CSV, which takes a few
  requests however big the study is, where `data_points/3` pages through
  every value. The frames are typed by the export's own variable lists,
  with the same dtypes per field type as `data_points/3` in the wide
  format, and a checkbox's columns are named after its options' values
  (`<variable>_<option value>`), as there.

  The fixed columns come first, named in snake case: `participant_id`,
  `participant_status`, `site_abbreviation` and `created_on` for the
  study; `participant_id`, `participant_status`, `created_on`,
  `instance_name` and `parent` for repeating data; `instance_id`,
  `participant_id`, `participant_status`, `created_on`, `sent_on`,
  `progress`, `completed_on`, `parent`, `survey_package_name` and
  `survey_package_id` for surveys. Their times are
  `{:naive_datetime, :microsecond}`, in the server's time zone.

  The export writes values marked missing as -95 to -99 in numeric and
  year fields and as the dates 1 January 2995 to 2999 in date fields;
  they become nulls, and with `missing_columns: true` their codes go in a
  `<variable>_missing` column of `{:s, 16}`. In other fields, and in
  checkboxes, the export leaves them empty, so the frames can't tell them
  from values never entered.

  ## Options

    * `:filters` - as for `CastorEDC.Export.participant_data/3`, such as
      `site_ids: [...]`
    * `:missing_columns` - add the missing-value columns; `false` by
      default
    * `:timeout` and `:poll_interval` - how long to wait for the export,
      and how soon to check on it first, as for
      `CastorEDC.Export.participant_data/3`
  """
  @spec participant_data(CastorEDC.client(), String.t(), keyword()) :: {:ok, wide()} | {:error, CastorEDC.Error.t()}
  def participant_data(client, study_id, opts \\ []) do
    {missing_columns, opts} = Keyword.pop(opts, :missing_columns, false)
    export_opts = [format: :csv, unzip: true] ++ Keyword.take(opts, [:filters, :timeout, :poll_interval])

    with {:ok, export} <- CastorEDC.Export.participant_data(client, study_id, export_opts) do
      repeating_data = Enum.map(CastorEDC.RepeatingData.stream_repeating_data(client, study_id), & &1.name)
      surveys = Enum.map(CastorEDC.Surveys.stream_surveys(client, study_id), & &1.name)

      {:ok, ParticipantData.read(export.files, repeating_data, surveys, missing_columns)}
    end
  rescue
    error in CastorEDC.Error -> {:error, error}
  end

  defp resource(columns, rows) do
    {:ok, rows.() |> Enum.to_list() |> Frame.from_rows(columns)}
  rescue
    error in CastorEDC.Error -> {:error, error}
  end

  defp value_type({list, of}), do: "#{list}(#{of})"
  defp value_type(type), do: Atom.to_string(type)

  defp flag(nil), do: nil
  defp flag(value), do: value not in [0, false]

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
