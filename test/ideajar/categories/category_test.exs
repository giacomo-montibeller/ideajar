defmodule Ideajar.Categories.CategoryTest do
  use Ideajar.DataCase, async: true

  alias Ideajar.Categories.Category

  describe "schema" do
    test "lists the expected fields" do
      assert MapSet.new(Category.__schema__(:fields)) ==
               MapSet.new([:id, :name, :display_order, :emoji, :inserted_at, :updated_at])
    end
  end

  # The seed migration populates display_order 1..8 with the canonical
  # names. To stay isolated from the seed, these tests use names not in
  # the canonical list and display_order values >= 100.
  describe "Repo.insert/1" do
    test "persists a fully populated category" do
      assert {:ok, %Category{} = cat} =
               Repo.insert(%Category{name: "test_alpha", display_order: 100, emoji: "🧪"})

      assert is_integer(cat.id)
      assert %DateTime{} = cat.inserted_at
      assert %DateTime{} = cat.updated_at
    end

    test "rejects a nil name with a NOT NULL constraint error" do
      assert_raise Postgrex.Error, ~r/not-null|NOT NULL/i, fn ->
        Repo.insert(%Category{name: nil, display_order: 101, emoji: "🧪"})
      end
    end

    test "rejects a nil emoji with a NOT NULL constraint error" do
      assert_raise Postgrex.Error, ~r/not-null|NOT NULL/i, fn ->
        Repo.insert(%Category{name: "test_no_emoji", display_order: 105, emoji: nil})
      end
    end

    test "rejects a duplicate display_order with a UNIQUE constraint error" do
      assert {:ok, _} =
               Repo.insert(%Category{name: "test_beta", display_order: 102, emoji: "🧪"})

      assert_raise Ecto.ConstraintError, ~r/categories_display_order_index/, fn ->
        Repo.insert(%Category{name: "test_gamma", display_order: 102, emoji: "🧪"})
      end
    end

    test "rejects a duplicate name with a UNIQUE constraint error" do
      assert {:ok, _} =
               Repo.insert(%Category{name: "test_delta", display_order: 103, emoji: "🧪"})

      assert_raise Ecto.ConstraintError, ~r/categories_name_index/, fn ->
        Repo.insert(%Category{name: "test_delta", display_order: 104, emoji: "🧪"})
      end
    end
  end
end
