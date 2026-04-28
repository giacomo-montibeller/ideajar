defmodule Ideajar.Ideas.Idea do
  @moduledoc """
  Schema and changeset for an idea persisted in the workspace.

  Slice 2 stores only the bare-minimum fields: title (required), description
  (free-text, no length cap), and url (optional, validated to start with
  http(s)://).

  Note on the type mapping: the SQLite migration uses `:text` for description
  and url so that values longer than 255 characters are stored without
  truncation. Ecto's `:string` here just means "binary" — the on-disk column is
  TEXT in either case for SQLite, which has no fixed-width string type.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @title_required "Il titolo è obbligatorio"
  @title_too_long "Il titolo non può superare i 200 caratteri"
  @url_invalid "Il link deve iniziare con http:// o https://"
  @url_too_long "Il link non può superare i 2000 caratteri"

  @castable_fields [:title, :description, :url]

  schema "ideas" do
    field :title, :string
    field :description, :string
    field :url, :string

    many_to_many :categories, Ideajar.Categories.Category, join_through: "idea_categories"

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds a changeset for creating an idea.

  Validation rules — the single source of truth for the slice 2 form:

    * `:title` — required, trimmed, max 200 chars
    * `:description` — optional, free-text, no length cap (A2)
    * `:url` — optional, trimmed; if present must parse as http(s):// with a
      non-empty host and be ≤ 2000 chars. The scheme check is
      case-insensitive but the value is stored verbatim (S5).

  Errors do not short-circuit: a submit with both an invalid title and an
  invalid url surfaces both messages.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = idea, attrs) do
    idea
    |> cast(attrs, @castable_fields)
    |> trim_text(:title)
    |> trim_text(:url)
    |> validate_required([:title], message: @title_required)
    |> validate_length(:title, max: 200, message: @title_too_long)
    |> validate_length(:url, max: 2000, message: @url_too_long)
    |> validate_url(:url)
  end

  # `update_change` runs only when the field is present in changes; it leaves
  # nil unchanged so optional fields stay optional. Trimming a string down to
  # "" makes `validate_required` fire with the canonical message.
  defp trim_text(changeset, field) do
    update_change(changeset, field, fn
      value when is_binary(value) -> String.trim(value)
      other -> other
    end)
  end

  defp validate_url(changeset, field) do
    cond do
      Keyword.has_key?(changeset.errors, field) ->
        # An earlier rule (e.g. length) already rejected this value; surfacing a
        # second error on the same field would be noisy.
        changeset

      get_change(changeset, field) in [nil, ""] ->
        changeset

      true ->
        validate_url_value(changeset, field, get_change(changeset, field))
    end
  end

  defp validate_url_value(changeset, field, value) do
    %URI{scheme: scheme, host: host} = URI.parse(value)

    cond do
      is_nil(scheme) -> add_error(changeset, field, @url_invalid)
      String.downcase(scheme) not in ["http", "https"] -> add_error(changeset, field, @url_invalid)
      host in [nil, ""] -> add_error(changeset, field, @url_invalid)
      true -> changeset
    end
  end
end
