defmodule IdeajarWeb.LoginController do
  use IdeajarWeb, :controller

  alias IdeajarWeb.SafeRedirect

  def new(conn, params) do
    if get_session(conn, :authenticated) do
      redirect(conn, to: "/")
    else
      return_to = sanitize(params)

      conn
      |> assign(:page_title, "ideajar — accesso")
      |> assign(:error, nil)
      |> render(:new, return_to: form_value(return_to))
    end
  end

  def create(conn, params) do
    return_to = sanitize(params)
    submitted = Map.get(params, "password", "")

    case Ideajar.Auth.authenticate(submitted) do
      :ok ->
        conn
        |> put_session(:authenticated, true)
        |> redirect(to: return_to)

      :error ->
        conn
        |> assign(:page_title, "ideajar — accesso")
        |> assign(:error, "Password errata")
        |> render(:new, return_to: form_value(return_to))
    end
  end

  # `SafeRedirect.normalize/1` collapses unsafe values to "/", so every value
  # leaving the controller (redirect target or template) is already safe.
  defp sanitize(params), do: params |> Map.get("return_to", "") |> SafeRedirect.normalize()

  # The form's hidden input shows "" rather than "/" when there is no specific
  # path to preserve — keeps an attacker-controlled string from echoing back
  # via the unsafe-URL path while still leaving redirects fully populated.
  defp form_value("/"), do: ""
  defp form_value(path), do: path
end
