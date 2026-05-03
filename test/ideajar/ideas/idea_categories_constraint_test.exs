defmodule Ideajar.Ideas.IdeaCategoriesConstraintTest do
  # Slice 11a: re-enabled async after the SQLite → Postgres migration.
  # The "Database busy" race that motivated async: false on SQLite is
  # gone (Postgres MVCC + sandbox isolation).
  use Ideajar.DataCase, async: true

  alias Ecto.Adapters.SQL
  alias Ideajar.Categories.Category
  alias Ideajar.Ideas.Idea

  defp insert_idea_with_categories!(title, category_names) do
    cats = Repo.all(from(c in Category, where: c.name in ^category_names))

    %Idea{title: title}
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:categories, cats)
    |> Repo.insert!()
  end

  describe "idea_categories — schema and association" do
    test "Idea schema declares :categories as a many_to_many association" do
      associations = Idea.__schema__(:associations)
      assert :categories in associations

      assoc = Idea.__schema__(:association, :categories)
      assert assoc.__struct__ == Ecto.Association.ManyToMany
      assert assoc.related == Ideajar.Categories.Category
      assert assoc.join_through == "idea_categories"
    end

    test "an idea can be inserted with categories via put_assoc and preloads them" do
      idea = insert_idea_with_categories!("Mare a Sirolo", ["mare", "viaggio"])

      reloaded = Repo.preload(Repo.get!(Idea, idea.id), :categories)
      names = Enum.map(reloaded.categories, & &1.name) |> Enum.sort()
      assert names == ["mare", "viaggio"]
    end
  end

  describe "FK semantics" do
    test "ON DELETE CASCADE on idea_categories.idea_id removes join rows when idea is deleted" do
      idea = insert_idea_with_categories!("temp", ["mare", "museo"])

      %{rows: [[joins_before]]} =
        SQL.query!(Repo, "SELECT COUNT(*) FROM idea_categories WHERE idea_id = $1", [idea.id])

      assert joins_before == 2

      Repo.delete!(idea)

      %{rows: [[joins_after]]} =
        SQL.query!(Repo, "SELECT COUNT(*) FROM idea_categories WHERE idea_id = $1", [idea.id])

      assert joins_after == 0

      # Categories are untouched.
      %{rows: [[cats]]} = SQL.query!(Repo, "SELECT COUNT(*) FROM categories", [])
      assert cats == 8
    end

    test "ON DELETE RESTRICT on idea_categories.category_id raises when a referenced category is deleted" do
      mare = Repo.get_by!(Category, name: "mare")
      _idea = insert_idea_with_categories!("ref", ["mare"])

      assert_raise Ecto.ConstraintError, ~r/foreign_key/, fn ->
        Repo.delete!(mare)
      end
    end
  end

  describe "PRIMARY KEY constraint on (idea_id, category_id)" do
    # Scenario: PRIMARY KEY on idea_categories prevents duplicate (idea_id, category_id) inserts
    test "inserting a duplicate (idea_id, category_id) row raises a constraint error" do
      idea = insert_idea_with_categories!("uniqcheck", ["mare"])
      mare = Repo.get_by!(Category, name: "mare")

      assert_raise Postgrex.Error, ~r/UNIQUE|unique|PRIMARY KEY|primary key/i, fn ->
        SQL.query!(
          Repo,
          "INSERT INTO idea_categories (idea_id, category_id) VALUES ($1, $2)",
          [idea.id, mare.id]
        )
      end
    end
  end
end
