defmodule Ideajar.Categories.Category do
  @moduledoc """
  Schema for a curated category attachable to ideas.

  Slice 3 ships a fixed seed of 8 categories and the application code never
  creates, edits, or deletes categories at runtime. The unique constraints
  on `name` and `display_order` are part of the contract — duplicates would
  break the chip ordering and the seed idempotency check.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "categories" do
    field :name, :string
    field :display_order, :integer

    timestamps(type: :utc_datetime)
  end
end
