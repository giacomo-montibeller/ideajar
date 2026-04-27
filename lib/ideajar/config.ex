defmodule Ideajar.Config do
  @moduledoc """
  Boot-time configuration validation. Called from `config/runtime.exs` before the
  endpoint config is finalized — a `raise` here aborts boot before the HTTP
  listener binds, so misconfiguration cannot reach traffic.
  """

  @min_password_length 12
  @min_secret_key_length 64

  @doc """
  Validates the workspace password and the endpoint secret key base.

  Returns `:ok` on success; raises `RuntimeError` with an operator-actionable
  message on failure.

  Opts:
    * `:workspace_password` — the resolved password value (env var + fallback)
    * `:secret_key_base` — the resolved endpoint secret_key_base
  """
  @spec validate!(keyword()) :: :ok
  def validate!(opts) do
    validate_password!(Keyword.get(opts, :workspace_password))
    validate_secret_key_base!(Keyword.get(opts, :secret_key_base))
    :ok
  end

  defp validate_password!(nil) do
    raise """
    WORKSPACE_PASSWORD is missing.
    Set the WORKSPACE_PASSWORD environment variable (or :workspace_password app
    config in dev/test) to a string of at least #{@min_password_length} characters.
    """
  end

  defp validate_password!(value)
       when is_binary(value) and byte_size(value) < @min_password_length do
    raise """
    WORKSPACE_PASSWORD is too short.
    Got #{byte_size(value)} characters; require at least #{@min_password_length}.
    """
  end

  defp validate_password!(value) when is_binary(value), do: :ok

  defp validate_secret_key_base!(nil) do
    raise """
    SECRET_KEY_BASE is missing.
    Set the SECRET_KEY_BASE environment variable to a string of at least
    #{@min_secret_key_length} bytes. Generate one with: mix phx.gen.secret
    """
  end

  defp validate_secret_key_base!(value)
       when is_binary(value) and byte_size(value) < @min_secret_key_length do
    raise """
    SECRET_KEY_BASE is too short.
    Got #{byte_size(value)} bytes; require at least #{@min_secret_key_length}.
    """
  end

  defp validate_secret_key_base!(value) when is_binary(value), do: :ok
end
