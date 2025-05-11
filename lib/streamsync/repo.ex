defmodule Streamsync.Repo do
  use Ecto.Repo,
    otp_app: :streamsync,
    adapter: Ecto.Adapters.SQLite3
end
