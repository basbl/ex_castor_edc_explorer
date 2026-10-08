defmodule CastorEDC.Explorer.FrameTest do
  use ExUnit.Case, async: true

  alias CastorEDC.Explorer.Frame
  alias CastorEDC.MissingValue
  alias CastorEDC.PartialDate

  test "writes every kind of decoded value as text" do
    assert Frame.text(nil) == nil
    assert Frame.text(MissingValue.new(97)) == nil
    assert Frame.text(:encrypted) == nil
    assert Frame.text("text") == "text"
    assert Frame.text(4.5) == "4.5"
    assert Frame.text(true) == "true"
    assert Frame.text(~D[2026-10-07]) == "2026-10-07"
    assert Frame.text(~T[12:30:00]) == "12:30:00"
    assert Frame.text(~N[2026-10-07 12:30:00]) == "2026-10-07T12:30:00"
    assert Frame.text(%PartialDate{year: 2020, month: 5}) == "2020-05"
    assert Frame.text({:upload, "scan.pdf"}) == "scan.pdf"
    assert Frame.text({:upload, nil}) == nil
    assert Frame.text({5, ~D[2026-10-07]}) == "5;2026-10-07"
    assert Frame.text({nil, ~D[2026-10-07]}) == ";2026-10-07"
    assert Frame.text({52.36, 4.9}) == "52.36;4.9"
    assert Frame.text(["0", "2"]) == "0;2"

    assert JSON.decode!(Frame.text(%{0 => %{0 => "5", 1 => MissingValue.new(95)}})) == %{
             "0" => %{"0" => "5", "1" => "##USER_MISSING_95##"}
           }
  end

  test "casts values to the column's dtype, and others to nil" do
    assert Frame.cast(3, {:f, 64}) === 3.0
    assert Frame.cast(3, {:s, 16}) == 3

    assert DateTime.compare(
             Frame.cast(~U[2026-10-07 12:30:00Z], {:datetime, :microsecond, "Etc/UTC"}),
             ~U[2026-10-07 12:30:00Z]
           ) == :eq

    assert Frame.cast(false, :boolean) == false
    assert Frame.cast(MissingValue.new(95), :boolean) == nil
    assert Frame.cast("not a number", {:f, 64}) == nil
  end
end
