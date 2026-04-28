defmodule Ideajar.Ideas.Idea do
  @moduledoc """
  Schema and changeset for an idea persisted in the workspace.

  Slice 2 fields: title (required, max 200, trimmed), description (free-text,
  no length cap), url (optional, max 2000, http(s):// only).

  Slice 3 adds a `many_to_many :categories` association via the
  `idea_categories` join table; the changeset enforces "at least one
  category" at the application level (SQLite cannot express the rule
  natively for many-to-many).

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
  @categories_required "Seleziona almeno una categoria"

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

  Validation rules — the single source of truth for the add-idea form:

    * `:title` — required, trimmed, max 200 chars
    * `:description` — optional, free-text, no length cap (A2)
    * `:url` — optional, trimmed; if present must parse as http(s):// with a
      non-empty host and be ≤ 2000 chars. The scheme check is
      case-insensitive but the value is stored verbatim (S5).
    * `:categories` — at least one required (slice 3). Caller must inject
      already-resolved `%Category{}` structs under the `:categories` (or
      `"categories"`) key; the changeset itself does no DB lookup.

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
    |> put_categories(attrs)
    |> validate_at_least_one_category()
  end

  # `put_categories` accepts both atom-keyed and string-keyed maps to handle
  # domain callers (atom keys) and LiveView form submissions (string keys).
  # When neither key is present `:categories` stays nil — `validate_length`
  # below then surfaces the canonical "almeno una categoria" error.
  defp put_categories(changeset, %{categories: cats}) when is_list(cats),
    do: put_assoc(changeset, :categories, cats)

  defp put_categories(changeset, %{"categories" => cats}) when is_list(cats),
    do: put_assoc(changeset, :categories, cats)

  defp put_categories(changeset, _attrs), do: changeset

  # NOTE: order matters — this validator only sees the categories association
  # if `put_assoc` ran before it. Keep `put_categories/2` in the pipeline
  # above this call.
  #
  # `validate_length/3` skips silently when the field is nil (no put_assoc
  # ran), so it cannot enforce "min: 1" on its own. We do the check by hand:
  # an empty list or a never-set categories field both surface the canonical
  # error.
  defp validate_at_least_one_category(changeset) do
    case get_field(changeset, :categories) do
      cats when is_list(cats) and cats != [] -> changeset
      _ -> add_error(changeset, :categories, @categories_required)
    end
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
      is_nil(scheme) ->
        add_error(changeset, field, @url_invalid)

      String.downcase(scheme) not in ["http", "https"] ->
        add_error(changeset, field, @url_invalid)

      host in [nil, ""] ->
        add_error(changeset, field, @url_invalid)

      true ->
        changeset
    end
  end
end
