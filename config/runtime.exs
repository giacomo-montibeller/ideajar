import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/ideajar start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :ideajar, IdeajarWeb.Endpoint, server: true
end

config :ideajar, IdeajarWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# ── Boot-time configuration validation ──────────────────────────────────
# Resolve workspace_password and secret_key_base from env vars (production)
# with fallback to compile-time config (dev/test). Validate before any
# further endpoint config is set: a `raise` here aborts boot before the
# HTTP listener binds, so misconfiguration cannot reach traffic.
workspace_password =
  System.get_env("WORKSPACE_PASSWORD") ||
    Application.get_env(:ideajar, :workspace_password)

secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
    :ideajar
    |> Application.get_env(IdeajarWeb.Endpoint, [])
    |> Keyword.get(:secret_key_base)

Ideajar.Config.validate!(
  workspace_password: workspace_password,
  secret_key_base: secret_key_base
)

config :ideajar, :workspace_password, workspace_password

config :ideajar, IdeajarWeb.Endpoint, secret_key_base: secret_key_base

if config_env() == :prod do
  # Slice 11a — Postgres adapter. `DATABASE_URL` is the canonical Phoenix
  # pattern (postgres://user:pass@host:port/db). Slice 11b deploy will
  # wire SECRET_KEY_BASE, PHX_HOST, etc. to Gigalixir env vars.
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: postgres://USER:PASS@HOST/DATABASE
      """

  config :ideajar, Ideajar.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  host = System.get_env("PHX_HOST") || "example.com"

  config :ideajar, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :ideajar, IdeajarWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ]

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :ideajar, IdeajarWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :ideajar, IdeajarWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
