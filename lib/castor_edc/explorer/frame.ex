defmodule CastorEDC.Explorer.Frame do
  # Builds frames from columns of Elixir values with given dtypes, so no
  # dtype is ever inferred from the data.
  @moduledoc false

  alias CastorEDC.MissingValue
  alias CastorEDC.PartialDate
  alias Explorer.DataFrame
  alias Explorer.Series

  @type column :: {String.t(), Series.dtype(), [term()]}

  @doc false
  @spec new([column()]) :: DataFrame.t()
  def new(columns) do
    DataFrame.new(for {name, dtype, values} <- columns, do: {name, Series.from_list(values, dtype: dtype)})
  end

  @doc false
  # Columns from rows (maps or structs), each column given as {name, key,
  # dtype}.
  @spec from_rows([map()], [{String.t(), term(), Series.dtype()}]) :: DataFrame.t()
  def from_rows(rows, columns) do
    new(for {name, key, dtype} <- columns, do: {name, dtype, Enum.map(rows, &cast(Map.get(&1, key), dtype))})
  end

  @doc false
  # A value as the dtype holds it: missing and encrypted values become
  # nil, and anything that isn't of the dtype becomes text.
  @spec cast(term(), Series.dtype()) :: term()
  def cast(%MissingValue{}, _dtype), do: nil
  def cast(:encrypted, _dtype), do: nil
  def cast(nil, _dtype), do: nil
  def cast(value, {:f, 64}) when is_number(value), do: value / 1
  def cast(value, {:s, _bits}) when is_integer(value), do: value
  def cast(%Date{} = value, :date), do: value
  def cast(%Time{} = value, :time), do: value
  def cast(%NaiveDateTime{} = value, {:naive_datetime, _unit}), do: value
  # Explorer holds a column's datetimes in one zone; the API's come in the
  # server's zone, so they're moved to UTC.
  def cast(%DateTime{} = value, {:datetime, _unit, "Etc/UTC"}),
    do: value |> DateTime.to_unix(:microsecond) |> DateTime.from_unix!(:microsecond)

  def cast(value, :boolean) when is_boolean(value), do: value
  def cast(value, :string), do: text(value)
  def cast(_value, _dtype), do: nil

  @doc false
  # The text of a decoded value: ISO 8601 for dates and times, `;` between
  # the parts of a checkbox, number-with-date or location, and JSON for a
  # grid.
  @spec text(term()) :: String.t() | nil
  def text(nil), do: nil
  def text(%MissingValue{}), do: nil
  def text(:encrypted), do: nil
  def text(value) when is_binary(value), do: value
  def text(value) when is_number(value) or is_atom(value), do: to_string(value)
  def text(%PartialDate{} = date), do: PartialDate.to_iso8601(date)
  def text(%module{} = value) when module in [Date, Time, NaiveDateTime, DateTime], do: module.to_iso8601(value)
  def text({:upload, name}), do: name
  def text({first, second}), do: Enum.map_join([first, second], ";", &(text(&1) || ""))
  def text(values) when is_list(values), do: Enum.map_join(values, ";", &text/1)

  def text(grid) when is_map(grid),
    do: grid |> Map.new(fn {row, cells} -> {row, Map.new(cells, &cell/1)} end) |> JSON.encode!()

  defp cell({column, %MissingValue{} = missing}), do: {column, MissingValue.to_wire(missing)}
  defp cell(cell), do: cell

  @doc false
  # The missing-value code of a value, if it's marked missing.
  @spec missing(term()) :: 95..99 | nil
  def missing(%MissingValue{code: code}), do: code
  def missing(_value), do: nil
end
