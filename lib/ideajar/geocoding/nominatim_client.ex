defmodule Ideajar.Geocoding.NominatimClient do
  @moduledoc """
  Real Nominatim HTTP client (slice 7a step 2).

  Reverse-geocoding lookups against the Nominatim public endpoint. Sends
  the required `User-Agent: ideajar/1.0` header (Nominatim usage policy)
  and disables Req's default retry/decompress on transport errors so a
  single network failure surfaces immediately as
  `{:error, :service_unavailable}` rather than blocking the caller.

  In tests, requests are routed through the canonical `Req.Test` plug
  (`{Req.Test, IdeajarStub}`) configured in `config/test.exs`. Each
  test installs its own stub via `Req.Test.stub(IdeajarStub, fn conn -> ... end)`.

  Response mapping (spec O5, S5, S6, CC1, CC3):

    * 200 + JSON with binary `display_name`        → `{:ok, name}`
    * 200 + JSON without `display_name`            → `{:error, :no_match}`
    * 200 + body that fails to parse as JSON       → `{:error, :service_unavailable}`
    * 404                                          → `{:error, :no_match}`
    * 5xx, network error, transport timeout        → `{:error, :service_unavailable}`
    * Any other non-success status                 → `{:error, :service_unavailable}`
  """

  @user_agent "ideajar/1.0"
  @default_base_url "https://nominatim.openstreetmap.org"

  @spec reverse_lookup(float, float) ::
          {:ok, String.t()} | {:error, :no_match | :service_unavailable}
  def reverse_lookup(lat, lng) do
    opts = Application.get_env(:ideajar, __MODULE__, [])
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    plug = get_in(opts, [:req_options, :plug])

    url = "#{base_url}/reverse?lat=#{lat}&lon=#{lng}&format=json"

    req_opts =
      [
        headers: [{"user-agent", @user_agent}],
        # Skip retries: transport/5xx failures must surface immediately so
        # the LV handler can flash `:service_unavailable` without blocking
        # the calling process for ~7s of exponential backoff.
        retry: false
      ]
      |> maybe_put_plug(plug)

    case Req.get(url, req_opts) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        extract_display_name(body)

      {:ok, %Req.Response{status: 404}} ->
        {:error, :no_match}

      {:ok, %Req.Response{status: status}} when status >= 500 ->
        {:error, :service_unavailable}

      {:ok, %Req.Response{}} ->
        {:error, :service_unavailable}

      {:error, _exception} ->
        {:error, :service_unavailable}
    end
  end

  defp maybe_put_plug(opts, nil), do: opts
  defp maybe_put_plug(opts, plug), do: Keyword.put(opts, :plug, plug)

  # Pre-decoded JSON map (Req auto-decodes when the response sets
  # `content-type: application/json`) — happy path.
  defp extract_display_name(%{"display_name" => name}) when is_binary(name),
    do: {:ok, name}

  defp extract_display_name(body) when is_map(body),
    do: {:error, :no_match}

  # Body returned as raw string: either Req didn't auto-decode (no JSON
  # content-type) or the server sent malformed JSON. Try a manual parse;
  # on failure treat as `:service_unavailable` (server bug, not a miss).
  defp extract_display_name(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"display_name" => name}} when is_binary(name) -> {:ok, name}
      {:ok, map} when is_map(map) -> {:error, :no_match}
      {:ok, _other} -> {:error, :service_unavailable}
      {:error, _} -> {:error, :service_unavailable}
    end
  end

  defp extract_display_name(_other), do: {:error, :service_unavailable}
end
