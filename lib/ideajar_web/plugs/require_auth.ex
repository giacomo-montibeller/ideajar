defmodule IdeajarWeb.RequireAuth do
  @moduledoc """
  Authentication boundary. Reads the `:authenticated` flag set by
  `LoginController` from the signed session cookie:

    * `true` → request continues
    * anything else (`nil`, `false`, tampered/invalid cookie) → on `GET`
      redirects to `/login?return_to=<encoded original path>`; on any other
      verb responds `403 Forbidden` with an empty body and halts.

  Plug.Session silently drops cookies whose signature does not validate, so a
  tampered cookie reaches us indistinguishable from "no cookie at all".
  """

  import Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{} = conn, _opts) do
    if get_session(conn, :authenticated) == true do
      conn
    else
      reject(conn)
    end
  end

  defp reject(%Plug.Conn{method: "GET"} = conn) do
    return_to = build_return_to(conn)

    conn
    |> Phoenix.Controller.redirect(to: "/login?return_to=" <> URI.encode_www_form(return_to))
    |> halt()
  end

  defp reject(conn) do
    conn
    |> send_resp(403, "")
    |> halt()
  end

  defp build_return_to(%Plug.Conn{request_path: path, query_string: ""}), do: path
  defp build_return_to(%Plug.Conn{request_path: path, query_string: q}), do: path <> "?" <> q
end
