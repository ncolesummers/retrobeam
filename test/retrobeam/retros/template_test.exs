defmodule Retrobeam.Retros.TemplateTest do
  use ExUnit.Case, async: true

  alias Retrobeam.Retros.Template

  doctest Retrobeam.Retros.Template

  @expected %{
    start_stop_continue: ["Start", "Stop", "Continue"],
    mad_sad_glad: ["Mad", "Sad", "Glad"],
    four_ls: ["Liked", "Learned", "Lacked", "Longed For"],
    sailboat: ["Wind", "Anchor", "Rocks", "Island"]
  }

  describe "all/0" do
    test "lists the named templates in display order" do
      assert Enum.map(Template.all(), & &1.key) ==
               [:start_stop_continue, :mad_sad_glad, :four_ls, :sailboat]
    end

    test "every template has a name, a description and columns" do
      for template <- Template.all() do
        assert is_binary(template.name) and template.name != ""
        assert is_binary(template.description) and template.description != ""
        assert template.columns != []
      end
    end
  end

  describe "columns/1" do
    for {key, names} <- @expected do
      test "#{key} has #{length(names)} columns with the right names and positions" do
        columns = Template.columns(unquote(key))

        assert length(columns) == length(unquote(names))
        assert Enum.map(columns, & &1.name) == unquote(names)
        assert Enum.map(columns, & &1.position) == Enum.to_list(0..(length(unquote(names)) - 1))
        assert Enum.all?(columns, &is_binary(&1.description))
      end
    end

    test "raises for custom, which has no fixed columns" do
      assert_raise ArgumentError, fn -> Template.columns(:custom) end
    end

    test "raises for an unknown template" do
      assert_raise ArgumentError, ~r/unknown retro template/, fn -> Template.columns(:nope) end
    end
  end

  describe "columns/2 for custom templates" do
    test "builds columns from 2 to 6 names" do
      assert {:ok, columns} = Template.columns(:custom, ["Wins", "Puzzles"])

      assert columns == [
               %{name: "Wins", description: nil, position: 0},
               %{name: "Puzzles", description: nil, position: 1}
             ]

      names = Enum.map(1..6, &"Column #{&1}")
      assert {:ok, columns} = Template.columns(:custom, names)
      assert Enum.map(columns, & &1.name) == names
    end

    test "accepts the string key sent by forms" do
      assert {:ok, [_, _]} = Template.columns("custom", ["A", "B"])
    end

    test "trims whitespace around names" do
      assert {:ok, columns} = Template.columns(:custom, ["  Wins ", "\tPuzzles\n"])
      assert Enum.map(columns, & &1.name) == ["Wins", "Puzzles"]
    end

    test "rejects fewer than 2 names" do
      assert Template.columns(:custom, []) == {:error, :too_few_columns}
      assert Template.columns(:custom, ["Only"]) == {:error, :too_few_columns}
    end

    test "rejects more than 6 names" do
      names = Enum.map(1..7, &"Column #{&1}")
      assert Template.columns(:custom, names) == {:error, :too_many_columns}
    end

    test "rejects blank names, including whitespace-only names" do
      assert Template.columns(:custom, ["Wins", ""]) == {:error, :blank_column_name}
      assert Template.columns(:custom, ["Wins", "   "]) == {:error, :blank_column_name}
    end

    test "rejects names over 40 characters" do
      assert {:ok, _} = Template.columns(:custom, ["Wins", String.duplicate("a", 40)])

      assert Template.columns(:custom, ["Wins", String.duplicate("a", 41)]) ==
               {:error, :column_name_too_long}
    end

    test "rejects duplicate names, ignoring case and surrounding spaces" do
      assert Template.columns(:custom, ["Wins", "wins "]) == {:error, :duplicate_column_names}
    end

    test "rejects names that are not text" do
      assert Template.columns(:custom, ["Wins", nil]) == {:error, :invalid_names}
      assert Template.columns(:custom, "Wins, Puzzles") == {:error, :invalid_names}
    end
  end

  describe "columns/2 for named templates" do
    test "returns the template's columns and ignores names" do
      assert Template.columns(:sailboat, ["ignored"]) == {:ok, Template.columns(:sailboat)}
      assert Template.columns("mad_sad_glad", []) == {:ok, Template.columns(:mad_sad_glad)}
    end

    test "ignores zero-width characters and Unicode forms" do
      assert Template.columns(:custom, ["\u200B", "Wins"]) == {:error, :blank_column_name}

      assert Template.columns(:custom, ["Wins", "Wins\u200B"]) ==
               {:error, :duplicate_column_names}

      nfc = "Caf\u00E9"
      nfd = "Cafe\u0301"
      assert Template.columns(:custom, [nfc, nfd]) == {:error, :duplicate_column_names}

      assert {:ok, [%{name: ^nfc}, %{name: "Wins"}]} =
               Template.columns(:custom, [nfd, "Wins\u200B"])
    end

    test "keeps joiners, so emoji sequences still render" do
      family = "\u{1F468}\u200D\u{1F469}\u200D\u{1F467}"
      assert {:ok, [%{name: ^family}, _]} = Template.columns(:custom, [family, "Wins"])
      assert Template.columns(:custom, ["\u200D", "Wins"]) == {:error, :blank_column_name}
    end

    test "caps codepoints so a name always fits its varchar column" do
      family = "\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}"
      assert String.length(family) == 1

      # 40 graphemes, but 280 codepoints.
      long = String.duplicate(family, 40)
      assert String.length(long) == 40
      assert Template.columns(:custom, [long, "Wins"]) == {:error, :column_name_too_long}

      assert {:ok, _} = Template.columns(:custom, [String.duplicate(family, 36), "Wins"])
    end

    test "rejects an unknown template" do
      assert Template.columns(:nope, []) == {:error, :unknown_template}
      assert Template.columns("nope", []) == {:error, :unknown_template}
    end
  end

  describe "keys/0 and fetch/1" do
    # Pinned on purpose: these keys are the Ecto.Enum values of a retro's
    # template field, so renaming or removing one breaks loading old retros.
    # Add new keys; never rename or remove existing ones.
    test "keys lists every template, custom last" do
      assert Template.keys() == [
               :start_stop_continue,
               :mad_sad_glad,
               :four_ls,
               :sailboat,
               :custom
             ]
    end

    test "fetch finds templates by atom or string key" do
      assert {:ok, %{key: :four_ls}} = Template.fetch(:four_ls)
      assert {:ok, %{key: :four_ls}} = Template.fetch("four_ls")
      assert {:ok, %{key: :custom, columns: []}} = Template.fetch(:custom)
      assert {:ok, %{key: :custom}} = Template.fetch("custom")
    end

    test "fetch rejects unknown keys without creating atoms" do
      assert Template.fetch(:nope) == :error
      assert Template.fetch("not_a_template_#{System.unique_integer()}") == :error
      assert Template.fetch(nil) == :error
      assert Template.fetch(42) == :error
    end

    test "custom/0 describes the custom template" do
      assert %{key: :custom, name: "Custom", columns: []} = Template.custom()
    end
  end

  describe "error_message/1" do
    test "has a message for every error" do
      for error <- [
            :invalid_names,
            :too_few_columns,
            :too_many_columns,
            :blank_column_name,
            :column_name_too_long,
            :duplicate_column_names,
            :unknown_template
          ] do
        assert is_binary(Template.error_message(error))
      end
    end
  end

  test "limits are exposed for forms" do
    assert Template.min_custom_columns() == 2
    assert Template.max_custom_columns() == 6
    assert Template.max_column_name_length() == 40
  end
end
