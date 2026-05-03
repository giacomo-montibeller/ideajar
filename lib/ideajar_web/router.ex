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

  # Authentication gate. Reads :authenticated from the signed session cookie.
  pipeline :require_auth do
    plug IdeajarWeb.RequireAuth
  end

  scope "/", IdeajarWeb do
    pipe_through :browser

    get "/login", LoginController, :new
    post "/login", LoginController, :create
  end

  # Slice 11b — public health check. Used by Gigalixir's HTTP probe;
  # bypasses :require_auth (no session needed) and uses the :api
  # pipeline so it returns JSON without going through the root layout.
  scope "/", IdeajarWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  scope "/", IdeajarWeb do
    pipe_through [:browser, :require_auth]

    live "/", IdeaLive.Index, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", IdeajarWeb do
  #   pipe_through :api
  # end
end
