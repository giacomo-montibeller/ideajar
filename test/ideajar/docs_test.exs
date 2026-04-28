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
end
