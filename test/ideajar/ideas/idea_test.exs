defmodule Ideajar.Ideas.IdeaTest do
  use Ideajar.DataCase, async: true

  alias Ideajar.Ideas.Idea

  describe "schema" do
    test "lists the expected fields" do
      assert Idea.__schema__(:fields) ==
               [:id, :title, :description, :url, :inserted_at, :updated_at]
    end
  end

  describe "Repo.insert/1" do
    test "persists a fully populated idea" do
      assert {:ok, %Idea{} = idea} =
               Repo.insert(%Idea{
                 title: "Mare",
                 description: "x",
                 url: "https://example.com"
               })

      assert is_integer(idea.id)
      assert %DateTime{} = idea.inserted_at
      assert %DateTime{} = idea.updated_at
    end

    test "rejects a nil title with a NOT NULL constraint error" do
      assert_raise Exqlite.Error, ~r/NOT NULL/, fn ->
        Repo.insert(%Idea{title: nil})
      end
    end
  end
end
