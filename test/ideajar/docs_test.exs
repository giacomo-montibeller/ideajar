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
  end
end
