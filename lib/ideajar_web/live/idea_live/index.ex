defmodule IdeajarWeb.IdeaLive.Index do
  @moduledoc """
  Workspace home: lists ideas (newest first) and lets the couple add a new
  one through an inline collapsible form.

  Mount enforces an authenticated session as defense-in-depth on top of the
  `IdeajarWeb.RequireAuth` plug — the plug already gates the HTTP request,
  but a future refactor that moved this LiveView under a different scope
  could lose that guarantee silently. The mount keeps the redirect behaviour
  byte-equivalent to the plug (`/login?return_to=%2F`).
  """

  use IdeajarWeb, :live_view

  alias Ideajar.Ideas

  @impl Phoenix.LiveView
  def mount(_params, %{"authenticated" => true}, socket) do
    {:ok,
     socket
     |> assign(:ideas, Ideas.list_ideas())
     |> assign(:form_visible?, false)}
  end

  def mount(_params, _session, socket) do
    {:ok, redirect_to_login(socket)}
  end

  defp redirect_to_login(socket) do
    Phoenix.LiveView.redirect(socket, to: "/login?return_to=%2F")
  end
end
