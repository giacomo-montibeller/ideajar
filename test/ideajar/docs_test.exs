defmodule Ideajar.DocsTest do
  # Acceptance D1 + D2 — README and conventions doc are authoritative for
  # operators and future contributors. These checks live in the test suite so
  # they fail loudly if a refactor strips required content.
  use ExUnit.Case, async: true

  describe "README.md (D1)" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "README.md"))}
    end

    test "documents the WORKSPACE_PASSWORD env var", %{content: content} do
      assert content =~ "WORKSPACE_PASSWORD"
    end

    test "documents the SECRET_KEY_BASE env var", %{content: content} do
      assert content =~ "SECRET_KEY_BASE"
    end

    test "explains how to generate a SECRET_KEY_BASE", %{content: content} do
      assert content =~ "mix phx.gen.secret"
    end

    test "describes the password rotation procedure", %{content: content} do
      assert content =~ ~r/rotazione password|password rotation/i
    end
  end

  describe "docs/conventions.md (D2)" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "docs/conventions.md"))}
    end

    test "states that the UI language is Italian", %{content: content} do
      assert content =~ ~r/lingua UI|UI language/i
    end

    test "lists canonical UI copy including the Entra button label", %{content: content} do
      assert content =~ "Entra"
    end

    test "lists the canonical Password errata error message", %{content: content} do
      assert content =~ "Password errata"
    end

    # Slice-2 UI copy — every canonical string from the plan's "UI copy
    # aggiunta" table must be present so the doc stays the single source of
    # truth for IT copy reuse.
    test "lists every canonical UI copy string introduced in slice 2", %{content: content} do
      slice_2_strings = [
        "+ Aggiungi idea",
        "Salva",
        "Salvataggio…",
        "Chiudi",
        "Titolo",
        "Descrizione",
        "Link",
        "Il titolo è obbligatorio",
        "Il titolo non può superare i 200 caratteri",
        "Il link deve iniziare con http:// o https://",
        "Il link non può superare i 2000 caratteri",
        "Apri link in una nuova scheda",
        "Nessuna idea ancora. Aggiungine una qui sopra.",
        "Idea aggiunta",
        "Salvataggio non riuscito, riprova"
      ]

      for needle <- slice_2_strings do
        assert content =~ needle, "missing slice-2 UI copy in conventions.md: #{needle}"
      end
    end
  end

  describe "README.md — slice 2 quick start" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "README.md"))}
    end

    test "documents mix ecto.migrate as part of the dev workflow", %{content: content} do
      assert content =~ "mix ecto.migrate"
    end
  end

  describe "docs/specs/add-idea-base.md — iter-2 sync" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "docs/specs/add-idea-base.md"))}
    end

    # Iter 2 added new invalid-link examples (data:, https://, ://example.com)
    # and removed the change_idea/2 helper from the architecture interface.
    test "carries the iter-2 invalid-link examples", %{content: content} do
      assert content =~ "data:text/html"
      assert content =~ "://example.com"
    end

    test "no longer references change_idea/2 in the architecture", %{content: content} do
      refute content =~ "change_idea/2"
    end
  end

  describe "docs/conventions.md — slice 3 UI copy" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "docs/conventions.md"))}
    end

    test "lists every canonical UI copy string introduced in slice 3", %{content: content} do
      slice_3_strings = [
        "Categorie *",
        "Scegli almeno una categoria",
        "Seleziona almeno una categoria",
        "Categoria non valida",
        "passeggiata",
        "mare",
        "museo",
        "ristorante",
        "sport",
        "cultura",
        "cinema",
        "viaggio"
      ]

      for needle <- slice_3_strings do
        assert content =~ needle, "missing slice-3 UI copy in conventions.md: #{needle}"
      end
    end
  end

  describe "docs/specs/categories-on-ideas.md — slice 3 spec sync" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "docs/specs/categories-on-ideas.md"))}
    end

    test "uses the iter-2 wording 'Manually re-invoking' for the seed-migration scenario",
         %{content: content} do
      assert content =~ "Manually re-invoking"
      refute content =~ ~r/Re-running mix ecto.migrate/i
    end

    test "carries the new boundary scenarios required after iter-2 review", %{
      content: content
    } do
      assert content =~ "PRIMARY KEY on idea_categories prevents duplicate"
      assert content =~ "Unauthenticated mount cannot reach the chip form"
      assert content =~ "Mixed-type duplicates"
      assert content =~ "hostile category_ids"
      assert content =~ "Ideajar.Categories module exposes only"
    end

    test "documents the legend asterisk and the helper-text contract", %{content: content} do
      assert content =~ ~s(legend reads "Categorie *")
      assert content =~ ~s("Scegli almeno una categoria")
    end

    test "carries an explicit XSS scenario for category-name escape", %{content: content} do
      assert content =~ "Scenario: XSS — a category whose name contains HTML is escaped"
    end
  end

  describe "docs/conventions.md — slice 4 UI copy" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "docs/conventions.md"))}
    end

    test "lists every canonical UI copy string introduced in slice 4", %{content: content} do
      slice_4_strings = [
        "Mostra tutte",
        "Nessuna idea per i filtri attivi.",
        "Tocca per filtrare: 1× opzionale · 2× obbligatoria · 3× rimuovi",
        "Filtra per:",
        "opzionale",
        "obbligatoria",
        "rimossa",
        "Filtri rimossi",
        "1 idea"
      ]

      for needle <- slice_4_strings do
        assert content =~ needle, "missing slice-4 UI copy in conventions.md: #{needle}"
      end
    end
  end

  describe "docs/conventions.md — slice 5 UI copy" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "docs/conventions.md"))}
    end

    test "lists every canonical UI copy string introduced in slice 5", %{content: content} do
      slice_5_strings = [
        # Form fieldset
        "Durata",
        # 5 chip labels
        "poche ore",
        "mezza giornata",
        "giornata",
        "weekend",
        "più giorni",
        # Error
        "Durata non valida",
        # Sub-labels (filter row)
        "Categorie",
        # Aria-label sub-block (SR)
        "Filtra per categoria",
        "Filtra per durata",
        # Helper text NULL exclusion
        "Le idee senza durata sono nascoste quando un filtro è attivo.",
        # Live-region
        "attiva,",
        # Compound suffixes
        ", filtri categoria attivi",
        ", filtri durata attivi"
      ]

      for needle <- slice_5_strings do
        assert content =~ needle, "missing slice-5 UI copy in conventions.md: #{needle}"
      end
    end
  end

  describe "CONTEXT.md — slice 5 closure" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "CONTEXT.md"))}
    end

    test "documents that ideas with NULL duration are excluded when the duration filter is active",
         %{content: content} do
      # The decision-closure clause must be present. Allow either Italian or
      # English wording. The key tokens are 'duration' / 'durata' + 'NULL' /
      # 'nil' + 'esclus' (escluso/esclusa/escluse).
      assert content =~ ~r/(duration|durata).*(NULL|nil).*esclus/i
    end

    test "no longer carries the open-decision marker for the duration case",
         %{content: content} do
      # Slice 5 closes the "Decisione UX aperta" lato durata. Other future
      # filters (slice 6 budget, slice 7 distance) may keep their own open
      # decisions, so we do NOT refute "Decisione UX aperta" globally — we
      # only refute it WITHIN a paragraph mentioning duration. Use a
      # scoped regex on the duration paragraph.
      duration_paragraph =
        content
        |> String.split(~r/\n\n+/)
        |> Enum.find(fn para ->
          para =~ ~r/durat/i and (para =~ ~r/NULL/i or para =~ ~r/nil/i)
        end)

      assert duration_paragraph, "no duration paragraph found in CONTEXT.md"

      refute duration_paragraph =~ ~r/Decisione UX aperta/i,
             "duration paragraph still marked as 'Decisione UX aperta'"
    end
  end

  describe "docs/conventions.md — slice 6 UI copy" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "docs/conventions.md"))}
    end

    test "lists every canonical UI copy string introduced in slice 6", %{content: content} do
      slice_6_strings = [
        # form fieldset label + filter sub-label
        "Budget",
        "gratis",
        "fino a 20€",
        "fino a 50€",
        "fino a 100€",
        "fino a 200€",
        "fino a 500€",
        "oltre 1000€",
        "Budget non valido",
        "Filtra per budget",
        "Le idee senza prezzo sono nascoste quando un filtro è attivo.",
        # aria-label suffix per chip on (used in 'gratis attiva', 'fino a X attiva', etc.)
        "attiva"
      ]

      for needle <- slice_6_strings do
        assert content =~ needle, "missing slice-6 UI copy in conventions.md: #{needle}"
      end
    end
  end

  describe "docs/conventions.md — live-region deprecation (slice 6)" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "docs/conventions.md"))}
    end

    test "marks the slice 4/5 live-region strings as deprecated", %{content: content} do
      # The deprecation marker should appear near the slice 4 + slice 5
      # live-region copy tables. Acceptable forms: "(deprecated slice 6 —
      # live-region rimosso)", "DEPRECATED slice 6", or similar.
      assert content =~ ~r/deprecated/i, "missing deprecation marker in conventions.md"
      assert content =~ ~r/live[ -]region/i, "deprecation context should mention live-region"
    end
  end

  describe "CONTEXT.md — slice 6 NULL-exclude uniform" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "CONTEXT.md"))}
    end

    test "documents NULL-exclude uniformity for both duration and budget filters",
         %{content: content} do
      # Should mention both 'durata' (slice 5) and 'budget' (slice 6) in the
      # same context, with NULL-exclude pattern documented as uniform.
      assert content =~ ~r/durata/i
      assert content =~ ~r/budget/i
      assert content =~ ~r/(NULL|nil).*esclus/i, "NULL-exclude pattern not documented"
    end

    test "no longer carries the slice 5 'NULL-pass per budget da rivalutare' open framing",
         %{content: content} do
      # Slice 5 step 9 had documented the duration-specific NULL-exclude with
      # deferred decision for budget. Slice 6 step 10 closes this — the
      # framing should now be uniform, not deferred.
      refute content =~ ~r/(da rivalutare|aperta).*budget/i,
             "CONTEXT.md still treats budget NULL-handling as open"
    end
  end
end
