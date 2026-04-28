defmodule Ideajar.Ideas.DurationTest do
  use ExUnit.Case, async: true

  alias Ideajar.Ideas.Duration

  describe "values/0" do
    test "returns the canonical 5 atoms in declared order" do
      assert Duration.values() ==
               [:poche_ore, :mezza_giornata, :giornata, :weekend, :piu_giorni]
    end
  end

  describe "parse/1 — happy path" do
    for atom <- [:poche_ore, :mezza_giornata, :giornata, :weekend, :piu_giorni] do
      test "parses #{inspect(atom)} from its stringified form" do
        assert Duration.parse(unquote(Atom.to_string(atom))) == {:ok, unquote(atom)}
      end
    end
  end

  describe "parse/1 — hostile input" do
    test "rejects an unknown string" do
      assert Duration.parse("schifoso") == :error
    end

    test "rejects an empty string" do
      assert Duration.parse("") == :error
    end

    test "rejects nil" do
      assert Duration.parse(nil) == :error
    end

    test "rejects an integer" do
      assert Duration.parse(42) == :error
    end

    test "rejects a list" do
      assert Duration.parse([]) == :error
    end

    test "rejects a map" do
      assert Duration.parse(%{}) == :error
    end
  end

  describe "label/1" do
    test "labels :poche_ore as 'poche ore'" do
      assert Duration.label(:poche_ore) == "poche ore"
    end

    test "labels :mezza_giornata as 'mezza giornata'" do
      assert Duration.label(:mezza_giornata) == "mezza giornata"
    end

    test "labels :giornata as 'giornata'" do
      assert Duration.label(:giornata) == "giornata"
    end

    test "labels :weekend as 'weekend'" do
      assert Duration.label(:weekend) == "weekend"
    end

    test "labels :piu_giorni as 'più giorni'" do
      assert Duration.label(:piu_giorni) == "più giorni"
    end

    test "no canonical label contains HTML special characters (XSS-via-atom pin)" do
      for atom <- Duration.values() do
        refute Duration.label(atom) =~ ~r/[<>&]/
      end
    end
  end
end
