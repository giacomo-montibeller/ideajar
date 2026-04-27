import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ideajar, Ideajar.Repo,
  database: Path.expand("../ideajar_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ideajar, IdeajarWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "GlAVpyV8XF8ce5an9NXF881POkROLoA1ON+uS9UuuZP56ehq/Lwa5cPbqa+1uszZ",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Workspace password for BDD test fixtures — the value used in the Background
# step of the device-password-auth feature.
config :ideajar, :workspace_password, "correct horse battery staple"

# Delay applied on wrong-password submissions. Default 500ms in dev/prod;
# zero in tests to keep the suite fast. The login_timing_test.exs file
# overrides this back to 500ms via Application.put_env (async: false).
config :ideajar, :wrong_password_delay_ms, 0
