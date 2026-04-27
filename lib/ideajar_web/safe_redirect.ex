defmodule IdeajarWeb.SafeRedirect do
  @moduledoc """
  Sanitizes a user-supplied `return_to` value into a redirect target safe to
  pass to `Phoenix.Controller.redirect(to: ...)`.

  Only single-leading-slash local paths are accepted. Any of the following are
  collapsed to `"/"`:

    * `nil` and the empty string
    * Protocol-relative URLs (`//evil.com`) — these resolve as cross-origin
      redirects in browsers
    * Absolute URLs (`https://`, `http://`, `javascript:`)
    * Values that do not start with `/`

  This is the boundary between untrusted query-string input and the
  `redirect/2` call site.
  """

  @safe_default "/"

  @spec normalize(String.t() | nil) :: String.t()
  def normalize("/" <> rest = path) do
    cond do
      # Protocol-relative URL like "//evil.com"
      String.starts_with?(rest, "/") -> @safe_default
      # Some browsers historically parsed "/\evil.com" as protocol-relative;
      # reject as defense-in-depth.
      String.starts_with?(rest, "\\") -> @safe_default
      # CRLF defends against header-injection at the redirect call site
      # (Plug already strips, but cheap belt-and-braces).
      String.contains?(path, ["\r", "\n"]) -> @safe_default
      true -> path
    end
  end

  def normalize(_), do: @safe_default
end
