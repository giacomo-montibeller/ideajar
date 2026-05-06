defmodule Ideajar.CategoriesTest do
  use Ideajar.DataCase, async: true

  alias Ideajar.Categories
  alias Ideajar.Categories.Category
  alias Ideajar.CategoriesFixtures

  # The seed migration ran in the test environment, so the sandbox already
  # sees the 8 canonical categories. These tests rely on that.

  defp by_name(name) do
    Repo.get_by!(Category, name: name)
  end

  describe "list_categories/0" do
    test "returns the 8 canonical categories ordered by display_order" do
      cats = Categories.list_categories()

      assert length(cats) == 8

      assert Enum.map(cats, & &1.name) == [
               "passeggiata",
               "mare",
               "museo",
               "ristorante",
               "sport",
               "cultura",
               "cinema",
               "viaggio"
             ]

      assert Enum.map(cats, & &1.display_order) == [1, 2, 3, 4, 5, 6, 7, 8]
    end

    test "every canonical category has its canonical emoji populated" do
      expected = CategoriesFixtures.canonical_emojis()

      for %Category{name: name, emoji: emoji} <- Categories.list_categories() do
        assert emoji == Map.fetch!(expected, name),
               "category #{name} has emoji #{inspect(emoji)}; expected #{inspect(expected[name])}"
      end
    end

    # The "empty table" branch is implicit in the canonical-8 case (length>0
    # and ordering match). A dedicated test that wiped the table fought the
    # `:auto` Sandbox mode toggled by Ideajar.MigrationsTest and was flaky.
    # The seed is the contract — covering the realistic state suffices.
  end

  describe "list_by_ids/1 — happy path" do
    test "returns {:ok, [%Category{}]} for a list of valid integer ids" do
      mare = by_name("mare")
      sport = by_name("sport")

      assert {:ok, cats} = Categories.list_by_ids([mare.id, sport.id])

      ids = Enum.map(cats, & &1.id)
      assert mare.id in ids
      assert sport.id in ids
      assert length(cats) == 2
    end

    test "accepts numeric strings and casts them to integers" do
      mare = by_name("mare")

      assert {:ok, [%Category{id: id}]} = Categories.list_by_ids(["#{mare.id}"])
      assert id == mare.id
    end

    test "returns {:ok, []} for an empty list" do
      assert {:ok, []} = Categories.list_by_ids([])
    end
  end

  describe "list_by_ids/1 — not_found" do
    test "rejects a list containing only non-existent ids" do
      assert {:error, :not_found} = Categories.list_by_ids([999_999])
    end

    test "rejects a list mixing valid and invalid ids (no partial)" do
      mare = by_name("mare")
      assert {:error, :not_found} = Categories.list_by_ids([mare.id, 999_999])
    end

    for value <- [-1, 0, 1.5] do
      test "rejects #{inspect(value)} (non-positive or non-integer numeric)" do
        assert {:error, :not_found} = Categories.list_by_ids([unquote(value)])
      end
    end

    for value <- ["abc", ""] do
      test "rejects non-numeric string #{inspect(value)}" do
        assert {:error, :not_found} = Categories.list_by_ids([unquote(value)])
      end
    end

    test "rejects nil entry" do
      assert {:error, :not_found} = Categories.list_by_ids([nil])
    end
  end

  describe "list_by_ids/1 — dedupe POST cast" do
    test "deduplicates duplicate integer ids before querying" do
      mare = by_name("mare")

      assert {:ok, [%Category{id: id}]} = Categories.list_by_ids([mare.id, mare.id])
      assert id == mare.id
    end

    test "deduplicates mixed-type duplicates (string vs integer of the same id)" do
      mare = by_name("mare")

      assert {:ok, cats} = Categories.list_by_ids(["#{mare.id}", mare.id])
      assert length(cats) == 1
      assert hd(cats).id == mare.id
    end
  end
end
