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

  alias CastorEDC.Explorer.Domains
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

  @label {"label", :label, :string}

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

  ## Option labels

  An option field (a radio, dropdown or checkbox) stores the value of the
  chosen option, such as `"1"`, where the user saw its name, such as
  `"Female"`. With `labels: true`, the long frame gets a `label` column
  of `:string` after `value`, holding the option's name (the names of the
  checked options, `;` between them, for a checkbox), and in the wide
  frames a radio or dropdown column holds the option's name instead of
  its value. A checkbox's wide columns stay `:boolean`, named after the
  options' values. A value that isn't one of its field's options keeps
  the value itself, and fields without options have no label.

  ## Options

    * `:format` - `:long` (the default) or `:wide`
    * `:labels` - the options' names, as above; `false` by default
    * `:missing_columns` - add the missing-value columns to wide frames;
      `false` by default
    * `:sources` and `:schema` - as for `CastorEDC.Tabular.data_points/3`
  """
  @spec data_points(CastorEDC.client(), String.t(), keyword()) ::
          {:ok, DataFrame.t() | wide()} | {:error, CastorEDC.Error.t()}
  def data_points(client, study_id, opts \\ []) do
    {missing_columns, opts} = Keyword.pop(opts, :missing_columns, false)
    {labels, opts} = Keyword.pop(opts, :labels, false)

    case Keyword.get(opts, :format, :long) do
      :long -> {:ok, long(client, study_id, opts, labels)}
      :wide -> {:ok, wide(client, study_id, opts, missing_columns, labels)}
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

  @survey_package_instances [
    {"survey_package_instance_id", :id, :string},
    {"survey_package_id", :survey_package_id, :string},
    {"survey_package_name", :survey_package_name, :string},
    {"participant_id", :participant_id, :string},
    {"site_id", :site_id, :string},
    {"site_name", :site_name, :string},
    {"status", :status, :string},
    {"progress", :progress, {:s, 64}},
    {"locked", :locked, :boolean},
    {"archived", :archived, :boolean},
    {"parent_id", :parent_id, :string},
    {"parent_type", :parent_type, :string},
    {"created_by", :created_by, :string},
    {"created_on", :created_on, @datetime},
    {"available_from", :available_from, @datetime},
    {"sent_on", :sent_on, @datetime},
    {"received_on", :received_on, @datetime},
    {"first_opened_on", :first_opened_on, @datetime},
    {"started_on", :started_on, @datetime},
    {"all_fields_filled_on", :all_fields_filled_on, @datetime},
    {"finished_on", :finished_on, @datetime},
    {"expire_on", :expire_on, @datetime}
  ]

  @repeating_data_instances [
    {"repeating_data_instance_id", :id, :string},
    {"name", :name, :string},
    {"repeating_data_id", :repeating_data_id, :string},
    {"repeating_data_name", :repeating_data_name, :string},
    {"participant_id", :participant_id, :string},
    {"status", :status, :string},
    {"archived", :archived, :boolean},
    {"parent_id", :parent_id, :string},
    {"parent_type", :parent_type, :string},
    {"created_by", :created_by, :string},
    {"created_on", :created_on, {:naive_datetime, :microsecond}}
  ]

  @queries [
    {"query_id", :id, :string},
    {"participant_id", :participant_id, :string},
    {"field_id", :field_id, :string},
    {"status", :status, :string},
    {"first_query_remark", :first_query_remark, :string},
    {"remarks", :remarks, {:s, 64}},
    {"created_by", :created_by, :string},
    {"created_on", :created_on, @datetime},
    {"updated_by", :updated_by, :string},
    {"updated_on", :updated_on, @datetime}
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
  The study's survey package instances, the survey packages sent to (or
  started for) participants, a row each.

  Columns: `survey_package_instance_id`, `survey_package_id` and
  `survey_package_name`, `participant_id`, `site_id` and `site_name`,
  `status`, `progress` (`{:s, 64}`, a percentage), `locked` and
  `archived` (`:boolean`), `parent_id` and `parent_type` (`"visit"` or
  `"repeating_data_instance"`, for one that belongs to either), `created_by`, and the
  times `created_on`, `available_from`, `sent_on`, `received_on`,
  `first_opened_on`, `started_on`, `all_fields_filled_on`, `finished_on`
  and `expire_on`, which are `{:datetime, :microsecond, "Etc/UTC"}`. The
  rest are `:string`.
  """
  @spec survey_package_instances(CastorEDC.client(), String.t()) ::
          {:ok, DataFrame.t()} | {:error, CastorEDC.Error.t()}
  def survey_package_instances(client, study_id) do
    resource(@survey_package_instances, fn ->
      for instance <- CastorEDC.Surveys.stream_survey_package_instances(client, study_id) do
        %{instance | parent_id: blank_to_nil(instance.parent_id), parent_type: parent_type(instance.parent_type)}
      end
    end)
  end

  @doc """
  The study's repeating data instances, such as each adverse event a
  participant had, a row each.

  Columns: `repeating_data_instance_id`, `name` (the instance's own),
  `repeating_data_id` and `repeating_data_name`, `participant_id`,
  `status`, `archived` (`:boolean`), `parent_id` and `parent_type` (what
  it was created from, if anything), `created_by`, and `created_on`,
  which is `{:naive_datetime, :microsecond}` in the server's time zone,
  as the API gives it. The rest are `:string`.

  The instances' values are in `data_points/3`, under their
  `repeating_data_instance_id` as `instance_id`.
  """
  @spec repeating_data_instances(CastorEDC.client(), String.t()) ::
          {:ok, DataFrame.t()} | {:error, CastorEDC.Error.t()}
  def repeating_data_instances(client, study_id) do
    resource(@repeating_data_instances, fn ->
      for instance <- CastorEDC.RepeatingData.stream_repeating_data_instances(client, study_id) do
        Map.merge(instance, %{
          repeating_data_id: instance.repeating_data && instance.repeating_data.id,
          parent_id: blank_to_nil(instance.parent_id),
          parent_type: blank_to_nil(instance.parent_type)
        })
      end
    end)
  end

  @doc """
  The queries raised on the study's values, a row each.

  Columns: `query_id`, `participant_id`, `field_id`, `status`,
  `first_query_remark`, `remarks` (`{:s, 64}`, how many remarks the
  query has), `created_by`, `created_on`, `updated_by` and `updated_on`.
  The times are `{:datetime, :microsecond, "Etc/UTC"}`, the rest
  `:string`.

  Join `field_id` with `fields/2` for the field's name and form.
  """
  @spec queries(CastorEDC.client(), String.t()) :: {:ok, DataFrame.t()} | {:error, CastorEDC.Error.t()}
  def queries(client, study_id) do
    resource(@queries, fn ->
      for query <- CastorEDC.Queries.stream_queries(client, study_id) do
        Map.put(query, :remarks, query.query_remarks && length(query.query_remarks))
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

  The export writes values marked missing as the dates 1 January 2995 to
  2999 in date fields, and as -95 to -99 in every other field but
  checkboxes; they become nulls, and with `missing_columns: true` their
  codes go in a `<variable>_missing` column of `{:s, 16}`. A checkbox's
  missing values are left empty, so its columns can't tell them from
  values never entered.

  ## Options

    * `:filters` - as for `CastorEDC.Export.participant_data/3`, such as
      `site_ids: [...]`
    * `:missing_columns` - add the missing-value columns; `false` by
      default
    * `:timeout` and `:poll_interval` - how long to wait for the export,
      and how soon to check on it first, as for
      `CastorEDC.Export.participant_data/3`
    * `:from` - read an export already made instead of running one: the
      `CastorEDC.Export` struct that `CastorEDC.Export.download/4` or
      `CastorEDC.Export.participant_data/3` returned, whether it holds the zip in memory, saved it with `:into`
      or unzipped it, or the path to such a zip or to the directory it was
      unzipped into. The client still fetches the names of the study's
      repeating data and surveys, to key their frames by. It can't be
      combined with the options above that run the export, and raises
      `ArgumentError` for an export that isn't a participant data export
      in CSV, hasn't been downloaded, or doesn't unzip.

  ## Examples

      {:ok, export} = CastorEDC.Export.download(client, study_id, export)
      {:ok, frames} = CastorEDC.Explorer.participant_data(client, study_id, from: export)

      {:ok, frames} = CastorEDC.Explorer.participant_data(client, study_id, from: "exports/study.zip")
  """
  @spec participant_data(CastorEDC.client(), String.t(), keyword()) :: {:ok, wide()} | {:error, CastorEDC.Error.t()}
  def participant_data(client, study_id, opts \\ []) do
    {missing_columns, opts} = Keyword.pop(opts, :missing_columns, false)
    {from, opts} = Keyword.pop(opts, :from)

    with {:ok, files} <- export_files(client, study_id, from, opts, []) do
      if Domains.grouped?(files),
        do: raise(ArgumentError, "the export is grouped by domain; read it with CastorEDC.Explorer.domains/3")

      repeating_data = Enum.map(CastorEDC.RepeatingData.stream_repeating_data(client, study_id), & &1.name)
      surveys = Enum.map(CastorEDC.Surveys.stream_surveys(client, study_id), & &1.name)

      {:ok, ParticipantData.read(files, repeating_data, surveys, missing_columns)}
    end
  rescue
    error in CastorEDC.Error -> {:error, error}
  end

  @doc """
  The study's data from a participant data export grouped by domain, as a
  frame per domain, keyed by the domain's abbreviation, such as `"DM"`.

  A study's domains map its fields, from any visit, repeating data or
  survey, to the variables of a domain, as in CDISC SDTM. The grouped
  export, which this runs in CSV, has a file per domain with a row per
  participant per visit, repeating data instance or survey that holds the
  domain's values, typed by the domain's own variable list:

  | Field type | Dtype |
  | --- | --- |
  | `numeric`, `slider` | `{:f, 64}` |
  | `year` | `{:s, 64}` |
  | `date` | `:date` |
  | `time` | `:time` |
  | `datetime` | `{:naive_datetime, :microsecond}` |
  | `numberdate` | `<variable>_number` of `{:f, 64}` and `<variable>_date` of `:date` |
  | `checkbox` | a `:boolean` column per option, `<variable>_<option value>` |
  | others | `:string` |

  The metadata columns come first, as the export names them, except for
  `created_on` (the participant's creation): `participant_id`,
  `participant_status`, `site_abbreviation`, `randomization_id`,
  `randomization_group`, `randomized_on`, `created_on`, `parent_type`,
  `parent_name`, `visit_name`, `visit_number` (`{:s, 64}`), `type`
  (`"Visit"`, `"Repeating data"` or `"Survey"`) and `name` (the visit or
  instance). Times are `{:naive_datetime, :microsecond}`, in the server's
  time zone, and the rest `:string`.

  Values marked missing are nulls; with `missing_columns: true`, their
  codes go in a `<variable>_missing` column of `{:s, 16}` (one per
  checkbox). With `labels: true`, the export also writes the options'
  names, and each radio and dropdown gets a `<variable>_label` column of
  `:string` holding them.

  ## Options

    * `:filters` - as for `CastorEDC.Export.participant_data/3`, such as
      `site_ids: [...]`
    * `:missing_columns` - add the missing-value columns; `false` by
      default
    * `:labels` - add the option-name columns; `false` by default
    * `:timeout` and `:poll_interval` - as for `participant_data/3`
    * `:from` - read a grouped export already made instead of running one,
      as for `participant_data/3`

  Raises `ArgumentError` when the export given as `:from` isn't grouped.
  """
  @spec domains(CastorEDC.client(), String.t(), keyword()) ::
          {:ok, %{String.t() => DataFrame.t()}} | {:error, CastorEDC.Error.t()}
  def domains(client, study_id, opts \\ []) do
    {missing_columns, opts} = Keyword.pop(opts, :missing_columns, false)
    {labels, opts} = Keyword.pop(opts, :labels, false)
    {from, opts} = Keyword.pop(opts, :from)
    options = [grouped: true, export_coded_options_as: if(labels, do: "values_and_names", else: "values")]

    with {:ok, files} <- export_files(client, study_id, from, opts, options) do
      if not Domains.grouped?(files),
        do: raise(ArgumentError, "the export isn't grouped by domain; read it with CastorEDC.Explorer.participant_data/3")

      {:ok, Domains.read(files, missing_columns, labels)}
    end
  rescue
    error in CastorEDC.Error -> {:error, error}
  end

  @doc """
  A frame from any of the client's results: a list, `CastorEDC.Page` or
  stream of structs (or maps), a row each, for resources this module has
  no function of its own for.

      CastorEDC.Countries.list_countries!(client) |> CastorEDC.Explorer.from_structs()
      CastorEDC.Visits.stream_visits(client, study_id) |> CastorEDC.Explorer.from_structs()

  Each field holding a plain value becomes a column named after it, in
  alphabetical order, as the client's structs define their fields. Fields holding a nested object or a list,
  such as a participant's `site`, are left out, as is the `extra` map;
  take those from the structs yourself.

  Unlike the other functions, the dtypes are inferred from the values, as
  nothing else describes them: `:string` for text, `{:s, 64}` for
  integers, `{:f, 64}` for floats (and integers mixed with them),
  `:boolean`, `:date`, `:time`, `{:naive_datetime, :microsecond}`, and
  `{:datetime, :microsecond, "Etc/UTC"}` for `DateTime`s, which are moved
  to UTC. A column whose values are of different kinds becomes `:string`,
  and one without any values `:null`. An empty list gives an empty frame
  without columns.

  Returns the frame, and raises the `CastorEDC.Error` of a stream whose
  request fails.
  """
  @spec from_structs(Enumerable.t() | CastorEDC.Page.t()) :: DataFrame.t()
  def from_structs(%CastorEDC.Page{entries: entries}), do: from_structs(entries)

  def from_structs(structs) do
    rows = Enum.to_list(structs)

    rows
    |> keys()
    |> Enum.flat_map(fn key -> struct_column(key, Enum.map(rows, &Map.get(&1, key))) end)
    |> Frame.new()
  end

  # The rows' keys, sorted, without a struct's own and its extra map.
  defp keys(rows) do
    rows |> Enum.flat_map(&Map.keys/1) |> Enum.uniq() |> Kernel.--([:__struct__, :extra]) |> Enum.sort()
  end

  defp struct_column(key, values) do
    case values |> Enum.reject(&is_nil/1) |> Enum.map(&kind/1) |> Enum.uniq() do
      [] ->
        [{to_string(key), :null, values}]

      kinds ->
        if :nested in kinds,
          do: [],
          else: [{to_string(key), inferred_dtype(kinds), cast_all(values, inferred_dtype(kinds))}]
    end
  end

  defp kind(value) when is_binary(value) or (is_atom(value) and not is_boolean(value)), do: :string
  defp kind(value) when is_boolean(value), do: :boolean
  defp kind(value) when is_integer(value), do: :integer
  defp kind(value) when is_float(value), do: :float
  defp kind(%Date{}), do: :date
  defp kind(%Time{}), do: :time
  defp kind(%NaiveDateTime{}), do: :naive_datetime
  defp kind(%DateTime{}), do: :datetime
  defp kind(_value), do: :nested

  defp inferred_dtype([:string]), do: :string
  defp inferred_dtype([:boolean]), do: :boolean
  defp inferred_dtype([:integer]), do: {:s, 64}
  defp inferred_dtype(kinds) when kinds in [[:float], [:integer, :float], [:float, :integer]], do: {:f, 64}
  defp inferred_dtype([:date]), do: :date
  defp inferred_dtype([:time]), do: :time
  defp inferred_dtype([:naive_datetime]), do: {:naive_datetime, :microsecond}
  defp inferred_dtype([:datetime]), do: @datetime
  defp inferred_dtype(_mixed), do: :string

  defp cast_all(values, :string), do: Enum.map(values, &Frame.text/1)
  defp cast_all(values, dtype), do: Enum.map(values, &Frame.cast(&1, dtype))

  @export_options [:filters, :timeout, :poll_interval]

  # The export's files as {name, contents}, from a new export with the
  # export options given, or the one given as :from.
  defp export_files(client, study_id, nil, opts, options) do
    export_opts = [format: :csv, unzip: true, options: options] ++ Keyword.take(opts, @export_options)

    with {:ok, export} <- CastorEDC.Export.participant_data(client, study_id, export_opts) do
      {:ok, ParticipantData.contents(export.files)}
    end
  end

  defp export_files(_client, _study_id, from, opts, _options) do
    case Keyword.take(opts, @export_options) do
      [] -> {:ok, ParticipantData.files(from)}
      given -> raise ArgumentError, ":from reads an export already made, so it takes no #{inspect(Keyword.keys(given))}"
    end
  end

  defp resource(columns, rows) do
    {:ok, rows.() |> Enum.to_list() |> Frame.from_rows(columns)}
  rescue
    error in CastorEDC.Error -> {:error, error}
  end

  defp value_type({list, of}), do: "#{list}(#{of})"
  defp value_type(type), do: Atom.to_string(type)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # A survey package instance's parent type is a code: 0 for none, 1 for a
  # visit, 2 for a repeating data instance.
  defp parent_type("0"), do: nil
  defp parent_type("1"), do: "visit"
  defp parent_type("2"), do: "repeating_data_instance"
  defp parent_type(type), do: blank_to_nil(type)

  defp flag(nil), do: nil
  defp flag(value), do: value not in [0, false]

  defp long(client, study_id, opts, false) do
    client
    |> Tabular.data_points(study_id, opts)
    |> Enum.map(&%{&1 | source: Atom.to_string(&1.source)})
    |> Enum.map(&Map.put(&1, :missing, Frame.missing(&1.value)))
    |> Frame.from_rows(@long)
  end

  defp long(client, study_id, opts, true) do
    schema = Keyword.get_lazy(opts, :schema, fn -> schema!(client, study_id) end)
    names = schema |> Map.values() |> Map.new(&{&1.field_id, option_names(&1)})
    {before, rest} = Enum.split_while(@long, &(elem(&1, 0) != "missing"))

    client
    |> Tabular.data_points(study_id, Keyword.put(opts, :schema, schema))
    |> Enum.map(&%{&1 | source: Atom.to_string(&1.source)})
    |> Enum.map(&Map.merge(&1, %{missing: Frame.missing(&1.value), label: label(&1.value, names[&1.field_id])}))
    |> Frame.from_rows(before ++ [@label | rest])
  end

  # An option field's names by their values; nil for other fields.
  defp option_names(%{option_group: %{options: [_option | _more] = options}}), do: Map.new(options, &{&1.value, &1.name})
  defp option_names(_column), do: nil

  # The name of an option value, or the names of a checkbox's, `;` between
  # them; a value that isn't an option keeps itself.
  defp label(_value, nil), do: nil
  defp label(value, names) when is_binary(value), do: Map.get(names, value, value)
  defp label(values, names) when is_list(values), do: Enum.map_join(values, ";", &label(&1, names))
  defp label(_value, _names), do: nil

  defp wide(client, study_id, opts, missing_columns, labels) do
    schema = Keyword.get_lazy(opts, :schema, fn -> schema!(client, study_id) end)
    sources = Keyword.get(opts, :sources, @sources)

    rows =
      client
      |> Tabular.data_points(study_id, Keyword.put(opts, :schema, schema))
      |> Enum.group_by(&{&1.source, &1.parent_id})

    frames =
      for {{context, parent_id} = key, columns} <- groups(schema, sources) do
        frame = frame(context, columns, Map.get(rows, key, []), missing_columns, labels)
        {context, parent_id, parent_name(columns), frame}
      end

    %{
      study: Enum.find_value(frames, &study_frame/1) || frame(:study, [], [], missing_columns, labels),
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

  defp frame(context, columns, rows, missing_columns, labels) do
    fixed =
      [{"participant_id", :participant_id}, {"site_id", :site_id}] ++
        if context == :study, do: [], else: [{"instance_id", :instance_id}]

    variables =
      columns
      |> Enum.sort_by(&{&1.position, variable_name(&1)})
      |> Enum.flat_map(&variable_columns(&1, missing_columns, labels))

    rows = Enum.sort_by(rows, &{&1.participant_id, &1.instance_id})

    Frame.new(
      Enum.map(fixed, fn {name, key} -> {name, :string, Enum.map(rows, &Map.get(&1, key))} end) ++
        Enum.map(variables, fn {name, dtype, read} -> {name, dtype, Enum.map(rows, read)} end)
    )
  end

  # The frame columns of a field: {name, dtype, a function reading the
  # column's value from a wide row}.
  defp variable_columns(column, missing_columns, labels) do
    names = for {name, _value} <- Tabular.wide_cells([column], %{}), do: name
    dtype = dtype(column)
    option_names = if labels and dtype == :string, do: option_names(column)
    values = for name <- names, do: {name, dtype, &Frame.cast(label_or_value(Map.get(&1, name), option_names), dtype)}

    if missing_columns do
      first = hd(names)
      values ++ [{"#{variable_name(column)}_missing", {:s, 16}, &Frame.missing(Map.get(&1, first))}]
    else
      values
    end
  end

  defp label_or_value(value, nil), do: value
  defp label_or_value(value, names) when is_binary(value) or is_list(value), do: label(value, names)
  defp label_or_value(value, _names), do: value

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
