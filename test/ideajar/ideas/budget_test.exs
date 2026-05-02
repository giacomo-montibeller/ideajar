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

  describe "index_to_value/1 (slice 9)" do
    test "index 0 → nil (filter inactive / form unspecified)" do
      assert Budget.index_to_value(0) == nil
    end

    test "indices 1..7 map to canonical integers in order" do
      assert Budget.index_to_value(1) == 0
      assert Budget.index_to_value(2) == 20
      assert Budget.index_to_value(3) == 50
      assert Budget.index_to_value(4) == 100
      assert Budget.index_to_value(5) == 200
      assert Budget.index_to_value(6) == 500
      assert Budget.index_to_value(7) == 1000
    end

    test "out-of-range integers clamp to nil (NOT :error)" do
      assert Budget.index_to_value(-1) == nil
      assert Budget.index_to_value(8) == nil
      assert Budget.index_to_value(99) == nil
      assert Budget.index_to_value(-999) == nil
    end

    test "non-integer inputs clamp to nil (safe-fallback)" do
      assert Budget.index_to_value("abc") == nil
      assert Budget.index_to_value(:atom) == nil
      assert Budget.index_to_value(nil) == nil
      assert Budget.index_to_value(3.5) == nil
      assert Budget.index_to_value([]) == nil
    end

    test "type contract pin (DM3a): return is integer | nil, never :error" do
      Enum.each([-1, 0, 1, 4, 7, 8, 99, "abc", nil, :atom], fn input ->
        result = Budget.index_to_value(input)

        assert is_integer(result) or is_nil(result),
               "expected integer | nil for #{inspect(input)}, got #{inspect(result)}"

        refute result == :error
      end)
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
