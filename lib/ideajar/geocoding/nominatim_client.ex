defmodule Ideajar.Geocoding.NominatimClient do
  @moduledoc """
  Slice 7a — Nominatim HTTP client.

  Step 1 ships a minimum-functional skeleton that exercises the
  `Req.Test` plug seam end-to-end so the slice's delegation path is
  proven before step 2 hardens the real implementation.

  When a `Req.Test` plug is configured for this module via
  `config :ideajar, Ideajar.Geocoding.NominatimClient, req_options:
  [plug: {Req.Test, IdeajarStub}]`, requests are routed through the
  test plug and a 200 response with a `display_name` field maps to
  `{:ok, name}`.

  When no plug is configured we fail safe with a friendly raise — the
  real production HTTP path (User-Agent, error mapping for all 9
  scenarios) lands in step 2.
  """

  @spec reverse_lookup(float, float) ::
          {:ok, String.t()} | {:error, :no_match | :service_unavailable}
  def reverse_lookup(lat, lng) do
    opts = Application.get_env(:ideajar, __MODULE__, [])
    plug = get_in(opts, [:req_options, :plug])

    if plug do
      url =
        "https://nominatim.openstreetmap.org/reverse?lat=#{lat}&lon=#{lng}&format=json"

      url
      |> Req.get!(plug: plug, decode_json: [keys: :strings])
      |> extract_display_name()
    else
      raise "Ideajar.Geocoding.NominatimClient not yet implemented (slice 7a step 2)"
    end
  end

  # Test plugs that omit the content-type header bypass Req's
  # auto-decoder; fall back to a manual parse so the slice's canonical
  # stub idiom (`Plug.Conn.send_resp/3`) works as documented in the
  # plan and spec.
  defp extract_display_name(%{status: 200, body: %{"display_name" => name}})
       when is_binary(name),
       do: {:ok, name}

  defp extract_display_name(%{status: 200, body: body}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"display_name" => name}} when is_binary(name) -> {:ok, name}
      _ -> {:error, :no_match}
    end
  end

  defp extract_display_name(_), do: {:error, :no_match}
end
