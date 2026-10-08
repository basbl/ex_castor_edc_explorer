defmodule CastorEDC.ExplorerTest do
  use ExUnit.Case, async: true

  alias CastorEDC.Explorer.Study
  alias Explorer.DataFrame

  describe "data_points/3" do
    test "gives a row per value, with fixed dtypes" do
      assert {:ok, frame} = CastorEDC.Explorer.data_points(Study.client(), Study.id())

      assert DataFrame.dtypes(frame) == %{
               "participant_id" => :string,
               "site_id" => :string,
               "source" => :string,
               "instance_id" => :string,
               "parent_id" => :string,
               "field_id" => :string,
               "variable_name" => :string,
               "value" => :string,
               "missing" => {:s, 16},
               "raw_value" => :string,
               "updated_on" => {:naive_datetime, :microsecond}
             }

      rows = DataFrame.to_rows(frame)
      assert length(rows) == 15

      assert %{"value" => "72.5", "missing" => nil, "site_id" => "site-1", "source" => "study", "instance_id" => nil} =
               value(rows, "P1", "weight")

      assert %{"value" => "2026-10-07T12:30:00", "updated_on" => ~N[2026-10-07 21:49:55.000000]} =
               value(rows, "P1", "seen")

      assert %{"value" => "0;2"} = value(rows, "P1", "family")
      assert %{"value" => nil, "missing" => 98, "raw_value" => "##USER_MISSING_98##"} = value(rows, "P2", "weight")
      assert %{"value" => nil, "missing" => nil, "raw_value" => "*encrypted*"} = value(rows, "P2", "note")

      assert %{"source" => "repeating_data", "instance_id" => "rdi-1", "parent_id" => "rd-1", "value" => "118"} =
               Enum.find(rows, &(&1["instance_id"] == "rdi-1"))
    end

    test "gives a frame per study, repeating data and survey in the wide format" do
      assert {:ok, %{study: study, repeating_data: repeating_data, surveys: surveys}} =
               CastorEDC.Explorer.data_points(Study.client(), Study.id(), format: :wide)

      assert DataFrame.names(study) ==
               ~w(participant_id site_id weight year visit seen time sex family_0 family_1 family_2 note bmi)

      assert DataFrame.dtypes(study) == %{
               "participant_id" => :string,
               "site_id" => :string,
               "weight" => {:f, 64},
               "year" => {:s, 64},
               "visit" => :date,
               "seen" => {:naive_datetime, :microsecond},
               "time" => :time,
               "sex" => :string,
               "family_0" => :boolean,
               "family_1" => :boolean,
               "family_2" => :boolean,
               "note" => :string,
               "bmi" => :string
             }

      assert [p1, p2] = DataFrame.to_rows(study)

      assert %{
               "participant_id" => "P1",
               "site_id" => "site-1",
               "weight" => 72.5,
               "year" => 1980,
               "visit" => ~D[2026-10-07],
               "time" => ~T[12:30:00.000000],
               "sex" => "1",
               "family_0" => true,
               "family_1" => false,
               "family_2" => true,
               "note" => "fine; thanks",
               "bmi" => "22.4"
             } = p1

      assert %{"weight" => nil, "note" => nil, "family_0" => nil, "year" => nil} = p2

      assert %{"Blood pressure" => blood_pressure} = repeating_data
      assert DataFrame.names(blood_pressure) == ~w(participant_id site_id instance_id sys)
      assert DataFrame.dtypes(blood_pressure)["sys"] == {:f, 64}
      assert DataFrame.to_columns(blood_pressure)["instance_id"] == ["rdi-1", "rdi-2"]

      assert %{"GAD-7" => gad} = surveys

      assert DataFrame.to_rows(gad) == [
               %{"participant_id" => "P2", "site_id" => "site-2", "instance_id" => "si-1", "gad" => "3"}
             ]
    end

    test "adds a column with the missing-value code of each variable when asked" do
      assert {:ok, %{study: study}} =
               CastorEDC.Explorer.data_points(Study.client(), Study.id(), format: :wide, missing_columns: true)

      assert DataFrame.dtypes(study)["weight_missing"] == {:s, 16}
      assert DataFrame.to_columns(study)["weight_missing"] == [nil, 98]
      assert DataFrame.to_columns(study)["family_missing"] == [nil, 95]
      refute "family_0_missing" in DataFrame.names(study)
    end

    test "keeps the columns of a study without values" do
      client = Study.client(%{"/data-points/study" => Study.page("items", [])})

      assert {:ok, %{study: study, repeating_data: %{"Blood pressure" => blood_pressure}}} =
               CastorEDC.Explorer.data_points(client, Study.id(), format: :wide)

      assert DataFrame.n_rows(study) == 0
      assert DataFrame.dtypes(study)["visit"] == :date
      assert DataFrame.n_rows(blood_pressure) == 2
    end

    test "keeps to the sources asked for" do
      assert {:ok, %{study: study, repeating_data: repeating_data, surveys: surveys}} =
               CastorEDC.Explorer.data_points(Study.client(), Study.id(), format: :wide, sources: [:survey])

      assert DataFrame.names(study) == ~w(participant_id site_id)
      assert repeating_data == %{}
      assert Map.keys(surveys) == ["GAD-7"]
    end

    test "returns the error of a failed request" do
      client = Study.client(%{"/field" => CastorEDC.Test.json(%{"detail" => "Forbidden"}, status: 403)})

      assert {:error, %CastorEDC.Error{status: 403}} = CastorEDC.Explorer.data_points(client, Study.id())
      assert {:error, %CastorEDC.Error{status: 403}} = CastorEDC.Explorer.data_points(client, Study.id(), format: :wide)
    end

    test "refuses an unknown format" do
      assert_raise ArgumentError, ~r/:format to be :long or :wide/, fn ->
        CastorEDC.Explorer.data_points(Study.client(), Study.id(), format: :tall)
      end
    end
  end

  defp value(rows, participant, variable) do
    Enum.find(rows, &(&1["participant_id"] == participant and &1["variable_name"] == variable))
  end

  describe "participants/2" do
    test "gives a row per participant" do
      assert {:ok, frame} = CastorEDC.Explorer.participants(Study.client(), Study.id())

      assert DataFrame.dtypes(frame)["created_on"] == {:datetime, :microsecond, "Etc/UTC"}
      assert DataFrame.dtypes(frame)["progress"] == {:f, 64}

      assert [p1, p2] = DataFrame.to_rows(frame)

      assert %{
               "participant_id" => "P1",
               "site_id" => "site-1",
               "site_name" => "Amsterdam",
               "status" => "open",
               "participant_status" => "Included",
               "progress" => 100.0,
               "locked" => false,
               "randomization_group" => 2,
               "created_on" => ~U[2026-10-07 19:06:33.000000Z]
             } = p1

      assert %{"participant_id" => "P2", "site_name" => nil, "participant_status" => nil, "progress" => 12.5} = p2
    end
  end

  describe "fields/2" do
    test "gives a row per field that holds values, in the study's order" do
      assert {:ok, frame} = CastorEDC.Explorer.fields(Study.client(), Study.id())

      assert DataFrame.to_columns(frame)["variable_name"] ==
               ~w(weight year visit seen time sex family note bmi sys gad)

      assert %{
               "field_id" => "f-weight",
               "field_type" => "numeric",
               "value_type" => "number",
               "context" => "study",
               "parent_name" => "Screening",
               "form_name" => "Baseline",
               "field_number" => 1,
               "required" => true,
               "hidden" => false,
               "units" => "kg",
               "min" => 30.0,
               "max" => 250.5
             } = frame |> DataFrame.to_rows() |> hd()

      assert %{"value_type" => "list(string)", "option_group_id" => "og-family", "required" => nil} =
               frame |> DataFrame.to_rows() |> Enum.find(&(&1["variable_name"] == "family"))
    end

    test "returns the error of a failed request" do
      client = Study.client(%{"/form" => CastorEDC.Test.json(%{"detail" => "Forbidden"}, status: 403)})
      assert {:error, %CastorEDC.Error{status: 403}} = CastorEDC.Explorer.fields(client, Study.id())
    end
  end

  describe "sites/2" do
    test "gives a row per site" do
      assert {:ok, frame} = CastorEDC.Explorer.sites(Study.client(), Study.id())

      assert DataFrame.to_rows(frame) == [
               %{
                 "site_id" => "site-1",
                 "name" => "Amsterdam",
                 "abbreviation" => "AMS",
                 "code" => nil,
                 "country_id" => 169,
                 "order" => 0,
                 "deleted" => nil
               },
               %{
                 "site_id" => "site-2",
                 "name" => "Utrecht",
                 "abbreviation" => nil,
                 "code" => nil,
                 "country_id" => nil,
                 "order" => nil,
                 "deleted" => true
               }
             ]
    end

    test "returns the error of a failed request" do
      client = Study.client(%{"/site" => CastorEDC.Test.json(%{"detail" => "Forbidden"}, status: 403)})
      assert {:error, %CastorEDC.Error{status: 403}} = CastorEDC.Explorer.sites(client, Study.id())
    end
  end

  describe "option_groups/2" do
    test "gives a row per option" do
      assert {:ok, frame} = CastorEDC.Explorer.option_groups(Study.client(), Study.id())

      assert DataFrame.to_rows(frame) == [
               %{
                 "option_group_id" => "og-sex",
                 "option_group_name" => "Sex",
                 "value" => "0",
                 "name" => "Male",
                 "order" => 0
               },
               %{
                 "option_group_id" => "og-sex",
                 "option_group_name" => "Sex",
                 "value" => "1",
                 "name" => "Female",
                 "order" => 1
               }
             ]
    end
  end
end
