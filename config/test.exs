import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :gameserver, Gameserver.Repo,
  database: Path.expand("../gameserver_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :gameserver, GameserverWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "y2u1w8JTb3hrXRz6t7vJJtZxBxSp/TQ0cmyOWoDIZMxrByj0IprQeCbvu810964L",
  server: false

# In test we don't send emails
config :gameserver, Gameserver.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Smaller map and fewer mobs for fast, predictable tests
config :gameserver,
  map_width: 30,
  map_height: 30,
  map_room_count: 8,
  map_room_dim_min: 3,
  map_room_dim_max: 7,
  mob_count: 3

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
