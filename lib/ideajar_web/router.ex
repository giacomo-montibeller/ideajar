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

  # Authentication gate. The plug is added in Step 5; this pipeline is defined
  # now so public routes (login, PWA assets) and protected routes can already
  # be wired with the right pipe_through chain.
  pipeline :require_auth do
  end

  scope "/", IdeajarWeb do
    pipe_through :browser

    get "/login", LoginController, :new
  end

  # Other scopes may use custom stacks.
  # scope "/api", IdeajarWeb do
  #   pipe_through :api
  # end
end
