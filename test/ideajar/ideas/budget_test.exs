defmodule Ideajar.Ideas.BudgetTest do
  use ExUnit.Case, async: true

  alias Ideajar.Ideas.Budget

  describe "values/0" do
    test "returns the canonical 7 buckets in declared order" do
      assert Budget.values() == [0, 20, 50, 100, 200, 500, 1000]
    end
  end

  describe "parse/1 — happy path" do
    for value <- [0, 20, 50, 100, 200, 500, 1000] do
      test "parses #{inspect(value)} from its stringified form" do
        assert Budget.parse(unquote(Integer.to_string(value))) == {:ok, unquote(value)}
      end
    end
  end

  describe "parse/1 — hostile input" do
    test "rejects an out-of-whitelist positive integer string" do
      assert Budget.parse("175") == :error
    end

    test "rejects a negative integer string" do
      assert Budget.parse("-50") == :error
    end

    test "rejects a non-numeric string" do
      assert Budget.parse("abc") == :error
    end

    test "rejects an empty string" do
      assert Budget.parse("") == :error
    end

    test "rejects nil" do
      assert Budget.parse(nil) == :error
    end

    test "rejects an integer (non-string)" do
      assert Budget.parse(42) == :error
    end

    test "rejects a list" do
      assert Budget.parse([]) == :error
    end

    test "rejects a map" do
      assert Budget.parse(%{}) == :error
    end
  end

  describe "label/1" do
    test "labels 0 as 'gratis'" do
      assert Budget.label(0) == "gratis"
    end

    test "labels 20 as 'fino a 20€'" do
      assert Budget.label(20) == "fino a 20€"
    end

    test "labels 50 as 'fino a 50€'" do
      assert Budget.label(50) == "fino a 50€"
    end

    test "labels 100 as 'fino a 100€'" do
      assert Budget.label(100) == "fino a 100€"
    end

    test "labels 200 as 'fino a 200€'" do
      assert Budget.label(200) == "fino a 200€"
    end

    test "labels 500 as 'fino a 500€'" do
      assert Budget.label(500) == "fino a 500€"
    end

    test "labels 1000 as 'oltre 1000€'" do
      assert Budget.label(1000) == "oltre 1000€"
    end

    test "no canonical label contains HTML special characters (XSS-via-bucket pin)" do
      for v <- Budget.values() do
        refute Budget.label(v) =~ ~r/[<>&]/
      end
    end
  end
end
