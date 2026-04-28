defmodule IdeajarWeb.PluralizationTest do
  use ExUnit.Case, async: true

  alias IdeajarWeb.Pluralization

  describe "idee_count/1" do
    test "0 → '0 idee'", do: assert(Pluralization.idee_count(0) == "0 idee")
    test "1 → '1 idea' (singolare)", do: assert(Pluralization.idee_count(1) == "1 idea")
    test "2 → '2 idee'", do: assert(Pluralization.idee_count(2) == "2 idee")
    test "100 → '100 idee'", do: assert(Pluralization.idee_count(100) == "100 idee")

    test "negative integer raises FunctionClauseError" do
      assert_raise FunctionClauseError, fn -> Pluralization.idee_count(-1) end
    end
  end
end
