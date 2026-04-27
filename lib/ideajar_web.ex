defmodule IdeajarWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use IdeajarWeb, :controller
      use IdeajarWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  # Paths served as static files by `Plug.Static` (configured in
  # `IdeajarWeb.Endpoint`). Because `Plug.Static` runs **before** the router,
  # any path matching one of these prefixes bypasses every router pipeline —
  # including `:require_auth`. PWA assets (`manifest.json`, `sw.js`, `icons`)
  # are reserved here even before slice 9 ships them, so a future router
  # refactor cannot accidentally gate them behind authentication.
  def static_paths,
    do: ~w(assets fonts images favicon.ico robots.txt manifest.json sw.js icons)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components
      import IdeajarWeb.CoreComponents

      # Common modules used in templates
      alias Phoenix.LiveView.JS
      alias IdeajarWeb.Layouts

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: IdeajarWeb.Endpoint,
        router: IdeajarWeb.Router,
        statics: IdeajarWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
