defmodule Ideajar.Auth do
  @moduledoc """
  Single source of truth for the workspace password check.

  The configured password is read from `Application.get_env(:ideajar,
  :workspace_password)` here and **does not leave this module** — controllers
  call `authenticate/2` with the user-submitted value and receive only `:ok`
  or `:error`.

  Wrong submissions sleep for `:wrong_password_delay_ms` to discourage casual
  brute force; the delay is configurable so tests can run without paying it.
  """

  @doc """
  Compares the submitted password against the configured `:workspace_password`
  in constant time. Returns `:ok` on match, `:error` otherwise.

  Opts:
    * `:wrong_password_delay_ms` — milliseconds to sleep before returning `:error`.
      Defaults to `Application.get_env(:ideajar, :wrong_password_delay_ms, 500)`.
  """
  @spec authenticate(String.t() | nil, keyword()) :: :ok | :error
  def authenticate(submitted, opts \\ [])

  def authenticate(submitted, opts) when is_binary(submitted) do
    configured = Application.get_env(:ideajar, :workspace_password)

    if is_binary(configured) and Plug.Crypto.secure_compare(configured, submitted) do
      :ok
    else
      sleep_for_wrong_password(opts)
      :error
    end
  end

  def authenticate(_other, opts) do
    sleep_for_wrong_password(opts)
    :error
  end

  defp sleep_for_wrong_password(opts) do
    delay =
      Keyword.get(
        opts,
        :wrong_password_delay_ms,
        Application.get_env(:ideajar, :wrong_password_delay_ms, 500)
      )

    if delay > 0, do: Process.sleep(delay)
    :ok
  end
end
