defmodule IdeajarWeb.PageController do
  use IdeajarWeb, :controller

  def home(conn, _params) do
    conn
    |> assign(:page_title, "ideajar — workspace privato")
    |> render(:home)
  end
end
