defmodule Ideajar.Ideas.Idea do
  @moduledoc """
  Schema and changeset for an idea persisted in the workspace.

  Slice 2 fields: title (required, max 200, trimmed), description (free-text,
  no length cap), url (optional, max 2000, http(s):// only).

  Slice 3 adds a `many_to_many :categories` association via the
  `idea_categories` join table; the changeset enforces "at least one
  category" at the application level (SQLite cannot express the rule
  natively for many-to-many).

  Slice 5 adds an optional `:duration` enum (`Ecto.Enum` whitelisted by
  `Ideajar.Ideas.Duration`); cast failures rewrite to the canonical
  `"Durata non valida"` via `override_duration_error/1`.

  Slice 6 adds an optional `:estimated_cost` integer with bucket whitelist
  `Ideajar.Ideas.Budget.values/0`. Validation uses a dual-path strategy:
  cast failures (non-numeric strings, e.g. `"abc"`, `"<script>"`) are
  rewritten by `override_estimated_cost_error/1`; valid integers outside
  the whitelist (e.g. `175`, `-50`) are rejected by `validate_inclusion/3`.
  Both paths surface the canonical `"Budget non valido"` error.

  Note on the type mapping: the SQLite migration uses `:text` for description
  and url so that values longer than 255 characters are stored without
  truncation. Ecto's `:string` here just means "binary" — the on-disk column is
  TEXT in either case for SQLite, which has no fixed-width string type.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ideajar.Ideas.Budget
  alias Ideajar.Ideas.Duration
  alias Ideajar.Ideas.TargetWindow

  @type t :: %__MODULE__{}

  @title_required "Il titolo è obbligatorio"
  @title_too_long "Il titolo non può superare i 200 caratteri"
  @url_invalid "Il link deve iniziare con http:// o https://"
  @url_too_long "Il link non può superare i 2000 caratteri"
  @categories_required "Seleziona almeno una categoria"
  @duration_invalid "Durata non valida"
  @cost_invalid "Budget non valido"
  @location_incomplete "Posizione incompleta"
  @location_invalid "Posizione non valida"
  @location_name_too_long "Il nome del luogo non può superare i 200 caratteri"

  @castable_fields [
    :title,
    :description,
    :url,
    :duration,
    :estimated_cost,
    :location_name,
    :lat,
    :lng,
    :target_start,
    :target_end,
    :target_granularity,
    :target_weekend_only
  ]

  schema "ideas" do
    field :title, :string
    field :description, :string
    field :url, :string
    field :duration, Ecto.Enum, values: Duration.values()
    field :estimated_cost, :integer
    field :location_name, :string
    field :lat, :float
    field :lng, :float
    field :target_start, :date
    field :target_end, :date
    field :target_granularity, Ecto.Enum, values: [:day, :month]
    field :target_weekend_only, :boolean, default: false

    many_to_many :categories, Ideajar.Categories.Category,
      join_through: "idea_categories",
      on_replace: :delete

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
    * `:duration` — optional (slice 5). Whitelist via `Ecto.Enum` values
      from `Duration.values/0`; canonical error `"Durata non valida"`.
    * `:estimated_cost` — optional (slice 6). Bucket whitelist via
      `Budget.values/0`. Canonical error `"Budget non valido"` for both
      cast failures and out-of-whitelist integers.

  Errors do not short-circuit: a submit with both an invalid title and an
  invalid url surfaces both messages.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = idea, attrs) do
    idea
    |> cast(attrs, @castable_fields)
    |> override_duration_error()
    |> override_estimated_cost_error()
    |> override_coordinate_errors()
    |> validate_inclusion(:estimated_cost, Budget.values(), message: @cost_invalid)
    |> validate_number(:lat,
      greater_than_or_equal_to: -90,
      less_than_or_equal_to: 90,
      message: @location_invalid
    )
    |> validate_number(:lng,
      greater_than_or_equal_to: -180,
      less_than_or_equal_to: 180,
      message: @location_invalid
    )
    |> trim_text(:title)
    |> trim_text(:url)
    |> trim_text(:location_name)
    |> validate_required([:title], message: @title_required)
    |> validate_length(:title, max: 200, message: @title_too_long)
    |> validate_length(:url, max: 2000, message: @url_too_long)
    |> validate_length(:location_name, max: 200, message: @location_name_too_long)
    |> validate_url(:url)
    |> put_categories(attrs)
    |> validate_at_least_one_category()
    |> validate_location_consistency()
    |> TargetWindow.validate_changeset()
  end

  # `Ecto.Enum` cast emits the generic `"is invalid"` message when the input
  # string is not a member of the whitelist. We override it on `:duration`
  # only with the canonical IT copy `"Durata non valida"` (AA22), preserving
  # any opts the cast attached (e.g. `validation: :cast`).
  defp override_duration_error(%Ecto.Changeset{errors: errors} = cs) do
    case Keyword.get(errors, :duration) do
      {"is invalid", opts} ->
        new_errors = Keyword.put(errors, :duration, {@duration_invalid, opts})
        %{cs | errors: new_errors}

      _ ->
        cs
    end
  end

  # Parallel to `override_duration_error/1`: the integer cast emits the
  # generic `"is invalid"` for non-numeric input (`"abc"`, `"<script>"`).
  # We rewrite to the canonical IT copy `"Budget non valido"` so the form
  # surfaces the same message users see for out-of-whitelist values
  # (BB2 — dual-path error coverage).
  defp override_estimated_cost_error(%Ecto.Changeset{errors: errors} = cs) do
    case Keyword.get(errors, :estimated_cost) do
      {"is invalid", opts} ->
        new_errors = Keyword.put(errors, :estimated_cost, {@cost_invalid, opts})
        %{cs | errors: new_errors}

      _ ->
        cs
    end
  end

  # Parallel to `override_duration_error/1` + `override_estimated_cost_error/1`:
  # the float cast emits the generic `"is invalid"` for non-numeric input
  # (`"abc"`, `"<script>"`). Rewrite both `:lat` and `:lng` to the canonical
  # `"Posizione non valida"` so users see the same message for cast failures
  # as for out-of-range values (CC6 — dual-path error coverage).
  defp override_coordinate_errors(%Ecto.Changeset{} = cs) do
    cs
    |> override_coordinate_error(:lat)
    |> override_coordinate_error(:lng)
  end

  defp override_coordinate_error(%Ecto.Changeset{errors: errors} = cs, field) do
    case Keyword.get(errors, field) do
      {"is invalid", opts} ->
        new_errors = Keyword.put(errors, field, {@location_invalid, opts})
        %{cs | errors: new_errors}

      _ ->
        cs
    end
  end

  # Cross-field validator (CC5): enforces the 3 valid states on the
  # `(location_name, lat, lng)` tuple.
  #
  #   (a) all 3 nil               → valid
  #   (b) name only, coords nil   → valid (utente scrive "Casa di nonna")
  #   (c) name + lat + lng all set → valid (full posizione)
  #   (d) any other combination    → invalid: `"Posizione incompleta"`
  #                                  on `:location_name` (centralizzato).
  #
  # Reads via `get_field/2` so it observes both the schema's persisted
  # values AND the changeset's pending changes — including the trimmed
  # `:location_name` (empty-string → nil after `trim_text/2`).
  defp validate_location_consistency(changeset) do
    name_present? = location_name_present?(changeset)
    lat_present? = not is_nil(get_field(changeset, :lat))
    lng_present? = not is_nil(get_field(changeset, :lng))

    case {name_present?, lat_present?, lng_present?} do
      # State (a): all 3 nil — no location.
      {false, false, false} -> changeset
      # State (b): name only — utente scrive "Casa di nonna".
      {true, false, false} -> changeset
      # State (c): name + both coords — full posizione.
      {true, true, true} -> changeset
      # State (d): everything else — invalid.
      _ -> add_error(changeset, :location_name, @location_incomplete)
    end
  end

  defp location_name_present?(changeset) do
    case get_field(changeset, :location_name) do
      nil -> false
      "" -> false
      _ -> true
    end
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
