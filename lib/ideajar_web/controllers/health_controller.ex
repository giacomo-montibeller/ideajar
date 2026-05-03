defmodule IdeajarWeb.HealthController do
  @moduledoc """
  Slice 11b — public health endpoint consumed by Gigalixir's HTTP
  probe. Returns a tiny JSON body so the platform can distinguish
  "container booted but app crashing" from "everything green" without
  any session cookie.
  """
  use IdeajarWeb, :controller

  def show(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end
end
