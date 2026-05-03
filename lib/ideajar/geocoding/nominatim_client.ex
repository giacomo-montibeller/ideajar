defmodule Ideajar.Geocoding.NominatimClient do
  @moduledoc """
  Real Nominatim HTTP client for forward geocoding (slice 7a UX rework).

  Forward-search lookups against the Nominatim public `/search` endpoint.
  Sends the required `User-Agent: ideajar/1.0` header (Nominatim usage
  policy) and disables Req's default retry so a single network failure
  surfaces immediately as `{:error, :service_unavailable}` rather than
  blocking the caller for ~7s of exponential backoff.

  In tests, requests are routed through the canonical `Req.Test` plug
  (`{Req.Test, IdeajarStub}`) configured in `config/test.exs`. Each
  test installs its own stub via
  `Req.Test.stub(IdeajarStub, fn conn -> ... end)`.

  Response mapping:

    * 200 + JSON array of well-formed results → `{:ok, results}`
    * 200 + JSON `[]`                          → `{:ok, []}`
    * 200 + body that fails to parse as JSON   → `{:error, :service_unavailable}`
    * 404                                      → `{:ok, []}`  (treated as "no results")
    * 5xx, network/transport error             → `{:error, :service_unavailable}`
    * Any other non-success status             → `{:error, :service_unavailable}`

  Each result in the JSON array is normalized: `display_name` passes
  through unchanged, `lat`/`lon` are parsed from string to float and
  `lon` is renamed to `lng` for internal consistency. Malformed
  results (missing fields, unparseable floats) are filtered out
  silently — only well-formed entries reach the caller.
  """

  @user_agent "ideajar/1.0"
  @default_base_url "https://nominatim.openstreetmap.org"
  @result_limit 5

  @spec search(String.t()) ::
          {:ok, [Ideajar.Geocoding.result()]} | {:error, :service_unavailable}
  def search(query) when is_binary(query) do
    opts = Application.get_env(:ideajar, __MODULE__, [])
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    plug = get_in(opts, [:req_options, :plug])

    url = "#{base_url}/search"

    req_opts =
      [
        headers: [{"user-agent", @user_agent}],
        params: [
          q: query,
          format: "json",
          limit: @result_limit,
          "accept-language": "it"
        ],
        # Skip retries: transport/5xx failures must surface immediately so
        # the LV handler can flash `:service_unavailable` without blocking
        # the calling process for ~7s of exponential backoff.
        retry: false
      ]
      |> maybe_put_plug(plug)

    case Req.get(url, req_opts) do
      {:ok, %Req.Response{status: 200, body: body}} when is_list(body) ->
        {:ok, Enum.flat_map(body, &normalize_result/1)}

      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, list} when is_list(list) ->
            {:ok, Enum.flat_map(list, &normalize_result/1)}

          _ ->
            {:error, :service_unavailable}
        end

      {:ok, %Req.Response{status: 404}} ->
        {:ok, []}

      {:ok, %Req.Response{status: status}} when status >= 500 ->
        {:error, :service_unavailable}

      {:ok, %Req.Response{}} ->
        {:error, :service_unavailable}

      {:error, _exception} ->
        {:error, :service_unavailable}
    end
  end

  @doc """
  Slice 9 follow-up — reverse-geocode lat/lng. Calls Nominatim's
  `/reverse` endpoint and returns the response's `display_name` when
  the body is well-formed. Defensive: any unexpected shape, transport
  error, missing stub, or parse failure collapses to
  `{:error, :service_unavailable}` so the LV handler can fall back to
  the generic "La mia posizione" label without crashing the LV
  process.
  """
  @spec reverse(float(), float()) :: {:ok, String.t()} | {:error, :service_unavailable}
  def reverse(lat, lng) when is_number(lat) and is_number(lng) do
    opts = Application.get_env(:ideajar, __MODULE__, [])
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    plug = get_in(opts, [:req_options, :plug])

    url = "#{base_url}/reverse"

    req_opts =
      [
        headers: [{"user-agent", @user_agent}],
        params: [
          lat: lat,
          lon: lng,
          format: "json",
          "accept-language": "it"
        ],
        retry: false
      ]
      |> maybe_put_plug(plug)

    try do
      case Req.get(url, req_opts) do
        {:ok, %Req.Response{status: 200, body: %{"display_name" => name}}}
        when is_binary(name) ->
          {:ok, name}

        {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
          case Jason.decode(body) do
            {:ok, %{"display_name" => name}} when is_binary(name) -> {:ok, name}
            _ -> {:error, :service_unavailable}
          end

        _ ->
          {:error, :service_unavailable}
      end
    rescue
      _ -> {:error, :service_unavailable}
    end
  end

  defp maybe_put_plug(opts, nil), do: opts
  defp maybe_put_plug(opts, plug), do: Keyword.put(opts, :plug, plug)

  # Normalize one Nominatim result; drop silently if any field is missing
  # or unparseable. Caller flat_maps so dropped results vanish from the
  # returned list.
  defp normalize_result(%{"display_name" => name, "lat" => lat_str, "lon" => lng_str})
       when is_binary(name) and is_binary(lat_str) and is_binary(lng_str) do
    with {lat, ""} <- Float.parse(lat_str),
         {lng, ""} <- Float.parse(lng_str) do
      [%{display_name: name, lat: lat, lng: lng}]
    else
      _ -> []
    end
  end

  defp normalize_result(_), do: []
end
