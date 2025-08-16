defmodule Streamsync.Repo.Migrations.CreateSyncJobsTable do
  use Ecto.Migration

  def change do
    create table(:sync_jobs) do
      add :from_provider, :string, null: false
      add :to_provider, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :sync_type, :string, null: false
      # TODO: song_count likely isn't the right field
      add :song_count, :integer, null: false
      add :synced_count, :integer, default: 0
      add :failed_count, :integer, default: 0
      add :metadata, :map, default: %{}
      add :error_message, :string
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:sync_jobs, [:user_id])
    create index(:sync_jobs, [:status])
  end
end
