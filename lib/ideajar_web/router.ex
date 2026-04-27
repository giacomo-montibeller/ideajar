defmodule IdeajarWeb.Router do
  use IdeajarWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {IdeajarWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", IdeajarWeb do
    pipe_through :browser
  end

  # Other scopes may use custom stacks.
  # scope "/api", IdeajarWeb do
  #   pipe_through :api
  # end
end
