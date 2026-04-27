defmodule IdeajarWeb.LoginController do
  use IdeajarWeb, :controller

  def new(conn, params) do
    if get_session(conn, :authenticated) do
      redirect(conn, to: "/")
    else
      return_to = Map.get(params, "return_to", "")

      conn
      |> assign(:page_title, "ideajar — accesso")
      |> render(:new, return_to: return_to)
    end
  end
end
