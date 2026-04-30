defmodule Ideajar.MixProject do
  use Mix.Project

  def project do
    [
      app: :ideajar,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Ideajar.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.5"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:req, "~> 0.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": [
        "compile",
        &copy_vendor_assets/1,
        "tailwind ideajar",
        "esbuild ideajar"
      ],
      "assets.deploy": [
        &copy_vendor_assets/1,
        "tailwind ideajar --minify",
        "esbuild ideajar --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end

  # Vendor JS/CSS files that must be served directly (not bundled by esbuild)
  # are mirrored from `assets/vendor/` to `priv/static/assets/vendor/` so
  # `Plug.Static` can serve them at `/assets/vendor/...`. Used for Leaflet's
  # UMD bundle (slice 7a) — the bundle exposes `window.L` only when loaded via
  # a `<script>` tag, so we need the file present on disk under priv/static.
  defp copy_vendor_assets(_args) do
    src_dir = Path.expand("assets/vendor", __DIR__)
    dest_dir = Path.expand("priv/static/assets/vendor", __DIR__)

    # Mirror only the files we actually serve as standalone vendor assets.
    # `daisyui.js`, `daisyui-theme.js`, `heroicons.js`, and `topbar.js` are
    # bundled by esbuild/tailwind and do not need to be copied.
    files_to_copy = ~w(leaflet.js leaflet.css)

    File.mkdir_p!(dest_dir)

    Enum.each(files_to_copy, fn name ->
      src = Path.join(src_dir, name)
      dest = Path.join(dest_dir, name)

      if File.exists?(src) do
        File.cp!(src, dest)
      end
    end)

    :ok
  end
end
