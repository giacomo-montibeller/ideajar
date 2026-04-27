defmodule Ideajar.IdeasTest do
  use Ideajar.DataCase, async: true

  alias Ideajar.Ideas
  alias Ideajar.Ideas.Idea

  describe "list_ideas/0" do
    test "returns an empty list when there are no ideas" do
      assert Ideas.list_ideas() == []
    end

    test "orders by inserted_at descending" do
      old = insert_idea!(%{title: "Vecchia"}, ~U[2026-04-26 10:00:00Z])
      new = insert_idea!(%{title: "Recente"}, ~U[2026-04-27 10:00:00Z])

      assert Enum.map(Ideas.list_ideas(), & &1.id) == [new.id, old.id]
    end

    test "tie-breaks ideas with the same inserted_at by id descending" do
      same = ~U[2026-04-27 10:00:00Z]
      first = insert_idea!(%{title: "First"}, same)
      second = insert_idea!(%{title: "Second"}, same)

      assert second.id > first.id
      assert Enum.map(Ideas.list_ideas(), & &1.id) == [second.id, first.id]
    end
  end

  describe "create_idea/1" do
    test "persists a valid idea and includes it in list_ideas/0" do
      assert {:ok, %Idea{id: id, title: "Mare"}} = Ideas.create_idea(%{title: "Mare"})
      assert Enum.any?(Ideas.list_ideas(), &(&1.id == id))
    end

    test "returns {:error, changeset} with the canonical title error" do
      assert {:error, %Ecto.Changeset{} = cs} = Ideas.create_idea(%{title: ""})
      assert {"Il titolo è obbligatorio", _} = Keyword.fetch!(cs.errors, :title)
    end
  end

  defp insert_idea!(attrs, %DateTime{} = at) do
    %Idea{}
    |> Map.merge(Map.new(attrs))
    |> Map.put(:inserted_at, at)
    |> Map.put(:updated_at, at)
    |> Repo.insert!()
  end
end
