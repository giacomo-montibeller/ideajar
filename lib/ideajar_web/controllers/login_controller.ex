defmodule IdeajarWeb.LoginController do
  use IdeajarWeb, :controller

  alias IdeajarWeb.SafeRedirect

  def new(conn, params) do
    if get_session(conn, :authenticated) do
      redirect(conn, to: "/")
    else
      return_to = Map.get(params, "return_to", "")

      conn
      |> assign(:page_title, "ideajar — accesso")
      |> assign(:error, nil)
      |> render(:new, return_to: return_to)
    end
  end

  def create(conn, params) do
    return_to_raw = Map.get(params, "return_to", "")
    submitted = Map.get(params, "password", "")

    case Ideajar.Auth.authenticate(submitted) do
      :ok ->
        conn
        |> put_session(:authenticated, true)
        |> redirect(to: SafeRedirect.normalize(return_to_raw))

      :error ->
        conn
        |> assign(:page_title, "ideajar — accesso")
        |> assign(:error, "Password errata")
        |> render(:new, return_to: return_to_raw)
    end
  end
end
