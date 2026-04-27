defmodule Ideajar.Ideas.Idea do
  @moduledoc """
  Schema for an idea persisted in the workspace.

  Slice 2 stores only the bare-minimum fields: title (required), description
  (free-text, no length cap), and url (optional, validated to start with
  http(s)://).

  Note on the type mapping: the SQLite migration uses `:text` for description
  and url so that values longer than 255 characters are stored without
  truncation. Ecto's `:string` here just means "binary" — the on-disk column is
  TEXT in either case for SQLite, which has no fixed-width string type.
  """

  use Ecto.Schema

  schema "ideas" do
    field :title, :string
    field :description, :string
    field :url, :string

    timestamps(type: :utc_datetime)
  end
end
