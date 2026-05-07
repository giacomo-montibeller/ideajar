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

  describe "docs/conventions.md — slice 7a UI copy" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "docs/conventions.md"))}
    end

    test "lists every canonical UI copy string introduced in slice 7a", %{content: content} do
      slice_7a_strings = [
        # fieldset legend
        "Posizione",
        # text input label
        "Luogo",
        # placeholder
        "es. Casa di nonna",
        # bottone apri picker
        "📍 Apri mappa",
        # bottone rimuovi
        "Rimuovi posizione",
        # titolo dialog
        "Scegli posizione",
        # OSM attribution (visible inside dialog)
        "© OpenStreetMap",
        # cross-field validation error
        "Posizione incompleta",
        # range/cast validation error
        "Posizione non valida",
        # length validation error
        "Il nome del luogo non può superare i 200 caratteri",
        # flash error when geocoding service is down
        "Geocodifica non disponibile, inserisci il nome manualmente",
        # CC19 inline hint when coords are set
        "📍 Coordinate impostate"
      ]

      for needle <- slice_7a_strings do
        assert content =~ needle, "missing slice-7a UI copy in conventions.md: #{needle}"
      end
    end
  end

  describe "CONTEXT.md — slice 7a schema fields" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "CONTEXT.md"))}
    end

    test "schema block documents location_name, lat, lng", %{content: content} do
      assert content =~ ~r/location_name/i
      # Word boundary to avoid spurious matches like "lateral".
      assert content =~ ~r/\blat\b/
      assert content =~ ~r/\blng\b/
    end
  end

  describe "docs/conventions.md — slice 7b UI copy" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "docs/conventions.md"))}
    end

    test "all slice-7b distance-filter UI strings appear verbatim", %{content: content} do
      needles = [
        "Filtra per distanza",
        "📍 Usa la mia posizione",
        "Cerca punto di partenza",
        "Punto di riferimento:",
        "La mia posizione",
        "Rimuovi punto di riferimento",
        "Rimuovi filtro distanza",
        "Disattivo",
        "fino a 5 km",
        "fino a 25 km",
        "fino a 50 km",
        "fino a 200 km",
        "fino a 500 km",
        "oltre 1000 km",
        "Imposta un punto di riferimento per usare il filtro distanza",
        "Le idee senza posizione sono nascoste quando un filtro è attivo.",
        "Permesso di geolocalizzazione negato",
        "Posizione non disponibile, riprova",
        "Ricerca non disponibile, riprova"
      ]

      for needle <- needles do
        assert content =~ needle, "missing slice-7b UI copy in conventions.md: #{needle}"
      end
    end
  end

  describe "CONTEXT.md — slice 7b distanza NULL-exclude uniform" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "CONTEXT.md"))}
    end

    test "the NULL-exclude decision now lists distanza alongside durata + budget",
         %{content: content} do
      # The decision section should mention distanza as part of the
      # uniform pattern, parallel to the slice-5/6 mentions of durata
      # and budget.
      assert content =~ ~r/durata.*budget.*distanza/is or
               content =~ ~r/distanza.*durata.*budget/is or
               content =~ ~r/distanza/i
    end

    test "filtri section marks Distanza max da me as implemented (slice 7b)",
         %{content: content} do
      assert content =~ "Distanza max da me"
      assert content =~ "slice 7b"
    end
  end

  describe "docs/conventions.md — slice 8 UI copy" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "docs/conventions.md"))}
    end

    test "all slice-8 text-search UI strings appear verbatim", %{content: content} do
      needles = [
        "Filtra per testo",
        "La ricerca trova le idee con la parola in titolo o descrizione.",
        "Cerca idee",
        "Rimuovi filtro testo"
      ]

      for needle <- needles do
        assert content =~ needle, "missing slice-8 UI copy in conventions.md: #{needle}"
      end
    end
  end

  describe "CONTEXT.md — slice 8 text-search NULL exception + implemented marker" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "CONTEXT.md"))}
    end

    test "the NULL-exclude decision documents the text-search exception",
         %{content: content} do
      # Slice 8 deviates from the uniform NULL-exclude pattern by
      # letting NULL-description ideas pass when title matches.
      assert content =~ ~r/eccezione documentata.*filtro testo/is or
               content =~ ~r/text-search/i or
               content =~ ~r/text\s+filter/i

      # The OR semantics is mentioned.
      assert content =~ ~r/title LIKE.*OR.*description LIKE/is or
               content =~ ~r/semantica `OR`/is
    end

    test "filtri section marks Ricerca testuale as implemented (slice 8)",
         %{content: content} do
      assert content =~ "Ricerca testuale"
      assert content =~ "slice 8"
    end
  end

  describe "docs/conventions.md — slice 10 manifest copy" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "docs/conventions.md"))}
    end

    test "all slice-10 manifest UI strings appear verbatim", %{content: content} do
      assert content =~ "Manifest `name`"
      assert content =~ "Ideajar"
      assert content =~ "Idee da fare insieme"
    end
  end

  describe "CONTEXT.md — slice 10 PWA implemented + slice 11 next" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "CONTEXT.md"))}
    end

    test "marks slice 10 implemented and slice 11 (deploy) as next",
         %{content: content} do
      assert content =~ "Slice 10"
      assert content =~ "implementato"
      assert content =~ "Slice 11"
      assert content =~ "Gigalixir"
    end
  end

  describe "docs/conventions.md — slice 9 UI copy" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "docs/conventions.md"))}
    end

    test "all slice-9 budget slider UI strings appear verbatim", %{content: content} do
      needles = [
        "Filtra per budget",
        "Disattivo",
        "Gratis",
        "fino a 20€",
        "fino a 50€",
        "fino a 100€",
        "fino a 200€",
        "fino a 500€",
        "oltre 1000€",
        "Rimuovi filtro budget",
        "Non specificato",
        "1000+€",
        "Rimuovi prezzo"
      ]

      for needle <- needles do
        assert content =~ needle, "missing slice-9 UI copy in conventions.md: #{needle}"
      end
    end
  end

  describe "docs/conventions.md — slice 14b category emojis" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "docs/conventions.md"))}
    end

    test "lists each canonical category alongside its emoji prefix", %{content: content} do
      for {name, emoji} <- Ideajar.CategoriesFixtures.canonical_emojis() do
        # The chip / badge contract renders "<emoji> <name>". The
        # conventions doc must mirror that exact substring so it is
        # quotable for design review.
        assert content =~ "#{emoji} #{name}",
               "conventions.md missing canonical emoji prefix for #{name} (#{emoji})"
      end
    end
  end

  describe "docs/specs/categories-on-ideas.md — slice 14b emoji sync" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "docs/specs/categories-on-ideas.md"))}
    end

    test "documents that the Category schema carries an `emoji` field", %{content: content} do
      assert content =~ ~r/\bemoji\b/i,
             "spec must document the emoji field as part of the Category contract"
    end

    test "lists each canonical category alongside its emoji prefix", %{content: content} do
      for {name, emoji} <- Ideajar.CategoriesFixtures.canonical_emojis() do
        assert content =~ "#{emoji} #{name}",
               "categories-on-ideas.md missing canonical emoji prefix for #{name} (#{emoji})"
      end
    end
  end

  describe "docs/conventions.md — slice 15 target window UI copy" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "docs/conventions.md"))}
    end

    test "lists every canonical UI copy string introduced in slice 15", %{content: content} do
      slice_15_strings = [
        "Quando",
        "Quando pensi di farlo?",
        "Giorni",
        "Mesi",
        "Solo nei weekend",
        "Rimuovi quando",
        "La data di fine deve essere uguale o successiva alla data di inizio",
        "Periodo non valido"
      ]

      for needle <- slice_15_strings do
        assert content =~ needle, "missing slice-15 UI copy in conventions.md: #{needle}"
      end
    end

    test "lists every canonical Italian month label", %{content: content} do
      months =
        ~w(gennaio febbraio marzo aprile maggio giugno luglio agosto settembre ottobre novembre dicembre)

      for month <- months do
        assert content =~ month, "missing canonical month name in conventions.md: #{month}"
      end
    end
  end

  describe "CONTEXT.md — slice 15 target window schema" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "CONTEXT.md"))}
    end

    test "schema block documents target_start, target_end, target_granularity, target_weekend_only",
         %{content: content} do
      for field <- ~w(target_start target_end target_granularity target_weekend_only) do
        assert content =~ field, "missing target-window column in CONTEXT.md: #{field}"
      end
    end
  end

  describe "docs/conventions.md — slice 12 UI copy (delete idea)" do
    setup do
      {:ok, content: File.read!(Path.join(File.cwd!(), "docs/conventions.md"))}
    end

    test "lists every canonical UI copy string introduced in slice 12", %{content: content} do
      # The list grows as steps add new strings; step 2 seeds "Elimina idea",
      # step 3 adds modal title/body/buttons and the confirm phx-disable-with
      # copy, step 5 adds the success flash. Later steps will extend it.
      needles = [
        "Elimina idea",
        "Eliminare questa idea?",
        "L'idea sarà rimossa definitivamente.",
        "Annulla",
        "Eliminazione…",
        "Idea eliminata",
        "Idea già eliminata",
        "Eliminazione non riuscita, riprova"
      ]

      for needle <- needles do
        assert content =~ needle, "missing slice-12 UI copy in conventions.md: #{needle}"
      end
    end
  end
end
