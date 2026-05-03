defmodule Ideajar.Repo do
  use Ecto.Repo,
    otp_app: :ideajar,
    adapter: Ecto.Adapters.Postgres
end
