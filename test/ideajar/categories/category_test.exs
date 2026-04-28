defmodule Ideajar.Categories.CategoryTest do
  use Ideajar.DataCase, async: true

  alias Ideajar.Categories.Category

  describe "schema" do
    test "lists the expected fields" do
      assert MapSet.new(Category.__schema__(:fields)) ==
               MapSet.new([:id, :name, :display_order, :inserted_at, :updated_at])
    end
  end

  describe "Repo.insert/1" do
    test "persists a fully populated category" do
      assert {:ok, %Category{} = cat} =
               Repo.insert(%Category{name: "passeggiata", display_order: 1})

      assert is_integer(cat.id)
      assert %DateTime{} = cat.inserted_at
      assert %DateTime{} = cat.updated_at
    end

    test "rejects a nil name with a NOT NULL constraint error" do
      assert_raise Exqlite.Error, ~r/NOT NULL/, fn ->
        Repo.insert(%Category{name: nil, display_order: 99})
      end
    end

    test "rejects a duplicate display_order with a UNIQUE constraint error" do
      assert {:ok, _} = Repo.insert(%Category{name: "uno", display_order: 100})

      assert_raise Ecto.ConstraintError, ~r/categories_display_order_index/, fn ->
        Repo.insert(%Category{name: "due", display_order: 100})
      end
    end

    test "rejects a duplicate name with a UNIQUE constraint error" do
      assert {:ok, _} = Repo.insert(%Category{name: "ripetuta", display_order: 101})

      assert_raise Ecto.ConstraintError, ~r/categories_name_index/, fn ->
        Repo.insert(%Category{name: "ripetuta", display_order: 102})
      end
    end
  end
end
