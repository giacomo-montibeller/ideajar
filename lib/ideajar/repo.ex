defmodule Ideajar.Repo do
  use Ecto.Repo,
    otp_app: :ideajar,
    adapter: Ecto.Adapters.SQLite3
end
