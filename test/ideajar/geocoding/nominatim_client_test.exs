defmodule Ideajar.Geocoding.NominatimClientTest do
  @moduledoc """
  Slice 7a step 1 — skeleton test for `Ideajar.Geocoding.NominatimClient`.

  The full HTTP behaviour (success/no-match/5xx/network-error/JSON-parse)
  lands in step 2. Step 1 only pins the public API surface and the
  fail-safe behaviour when the test plug seam is not configured.
  """

  # async: false — the "no plug configured" test mutates the global
  # `Application` env for `Ideajar.Geocoding.NominatimClient`. Running
  # serially keeps unrelated tests (which rely on the test-config plug
  # seam) from observing the deleted state.
  use ExUnit.Case, async: false

  describe "reverse_lookup/2" do
    test "is exported with arity 2" do
      Code.ensure_loaded!(Ideajar.Geocoding.NominatimClient)
      assert function_exported?(Ideajar.Geocoding.NominatimClient, :reverse_lookup, 2)
    end

    test "raises a friendly not-yet-implemented error when no Req.Test plug is configured" do
      previous = Application.get_env(:ideajar, Ideajar.Geocoding.NominatimClient)
      Application.delete_env(:ideajar, Ideajar.Geocoding.NominatimClient)

      try do
        assert_raise RuntimeError, ~r/not yet implemented/, fn ->
          Ideajar.Geocoding.NominatimClient.reverse_lookup(43.5, 13.6)
        end
      after
        if previous do
          Application.put_env(:ideajar, Ideajar.Geocoding.NominatimClient, previous)
        end
      end
    end
  end
end
