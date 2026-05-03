defmodule Ideajar.ReleaseTest do
  @moduledoc """
  Slice 11b — smoke tests for `Ideajar.Release`. The module is invoked
  in production via `bin/ideajar eval "Ideajar.Release.migrate"` after
  every deploy; it must export the canonical Phoenix release contract
  (`migrate/0`, `rollback/2`) and load the application before running
  Ecto.Migrator. We pin the surface here so an accidental rename or
  signature change fails CI before it can reach production.
  """
  use ExUnit.Case, async: true

  test "migrate/0 is exported with arity 0" do
    Code.ensure_loaded!(Ideajar.Release)
    assert function_exported?(Ideajar.Release, :migrate, 0)
  end

  test "rollback/2 is exported with arity 2" do
    Code.ensure_loaded!(Ideajar.Release)
    assert function_exported?(Ideajar.Release, :rollback, 2)
  end

  test "the @app attribute resolves the configured ecto_repos" do
    # Indirect pin: `migrate/0` calls `Application.fetch_env!(:ideajar, :ecto_repos)`
    # which must return our actual Repo. If a future maintainer renames the
    # OTP app or drops the Repo from config, this assertion catches it.
    assert [Ideajar.Repo] = Application.fetch_env!(:ideajar, :ecto_repos)
  end
end
