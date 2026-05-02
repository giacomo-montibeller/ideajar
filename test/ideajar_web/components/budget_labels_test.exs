defmodule IdeajarWeb.Components.BudgetLabelsTest do
  @moduledoc """
  Slice 9 — UI copy IT per il budget slider in due context (filter
  cumulative + form single-value). I label vivono nel web layer perché
  la prosa IT è delivery-side, non domain.
  """
  use ExUnit.Case, async: true

  alias IdeajarWeb.Components.BudgetLabels

  describe "filter/1 (slice 9 — cumulative IT labels)" do
    test "index 0 → 'Disattivo'" do
      assert BudgetLabels.filter(0) == "Disattivo"
    end

    test "index 1 → 'Gratis'" do
      assert BudgetLabels.filter(1) == "Gratis"
    end

    test "indices 2..6 → 'fino a X€'" do
      assert BudgetLabels.filter(2) == "fino a 20€"
      assert BudgetLabels.filter(3) == "fino a 50€"
      assert BudgetLabels.filter(4) == "fino a 100€"
      assert BudgetLabels.filter(5) == "fino a 200€"
      assert BudgetLabels.filter(6) == "fino a 500€"
    end

    test "index 7 → 'oltre 1000€' (open-ended)" do
      assert BudgetLabels.filter(7) == "oltre 1000€"
    end

    test "OOR safe-fallback → 'Disattivo' (DM4a)" do
      assert BudgetLabels.filter(-1) == "Disattivo"
      assert BudgetLabels.filter(99) == "Disattivo"
      assert BudgetLabels.filter("abc") == "Disattivo"
      assert BudgetLabels.filter(:atom) == "Disattivo"
      assert BudgetLabels.filter(nil) == "Disattivo"
    end
  end

  describe "form/1 (slice 9 — single-value IT labels)" do
    test "index 0 → 'Non specificato'" do
      assert BudgetLabels.form(0) == "Non specificato"
    end

    test "index 1 → 'Gratis'" do
      assert BudgetLabels.form(1) == "Gratis"
    end

    test "indices 2..6 → 'X€' (NO 'fino a' prefix)" do
      assert BudgetLabels.form(2) == "20€"
      assert BudgetLabels.form(3) == "50€"
      assert BudgetLabels.form(4) == "100€"
      assert BudgetLabels.form(5) == "200€"
      assert BudgetLabels.form(6) == "500€"
    end

    test "index 7 → '1000+€' (single-value open-ended)" do
      assert BudgetLabels.form(7) == "1000+€"
    end

    test "OOR safe-fallback → 'Non specificato' (DM5a)" do
      assert BudgetLabels.form(-1) == "Non specificato"
      assert BudgetLabels.form(99) == "Non specificato"
      assert BudgetLabels.form("abc") == "Non specificato"
      assert BudgetLabels.form(:atom) == "Non specificato"
      assert BudgetLabels.form(nil) == "Non specificato"
    end
  end

  describe "filter vs form divergence pin" do
    test "index 0 differs (filter 'Disattivo' vs form 'Non specificato')" do
      assert BudgetLabels.filter(0) == "Disattivo"
      assert BudgetLabels.form(0) == "Non specificato"
    end

    test "index 1 converges ('Gratis' for both — semantica '0€' è la stessa)" do
      assert BudgetLabels.filter(1) == BudgetLabels.form(1)
      assert BudgetLabels.filter(1) == "Gratis"
    end

    test "indices 2..7 diverge: filter has 'fino a' prefix, form is single value" do
      for idx <- 2..6 do
        filter = BudgetLabels.filter(idx)
        form = BudgetLabels.form(idx)
        assert filter != form, "expected divergence at index #{idx}"
        assert filter =~ "fino a "
        refute form =~ "fino a "
      end

      assert BudgetLabels.filter(7) == "oltre 1000€"
      assert BudgetLabels.form(7) == "1000+€"
    end
  end
end
