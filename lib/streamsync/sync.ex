defmodule Streamsync.Sync do
  @moduledoc """
  The Sync context for managing music sync jobs between platforms.
  """

  import Ecto.Query, warn: false
  alias Streamsync.Repo
  alias Streamsync.Sync.Job
  alias Streamsync.Sync.SyncJob

  defmodule Job do
    @moduledoc """
    Schema for sync jobs that track syncing songs between platforms.
    """
    use Ecto.Schema
    import Ecto.Changeset

    @valid_providers ["spotify", "tidal", "apple_music"]

    schema "sync_jobs" do
      field :from_provider, :string
      field :to_provider, :string
      field :status, Ecto.Enum, values: [:pending, :processing, :completed, :failed]
      field :sync_type, :string
      field :song_count, :integer
      field :synced_count, :integer, default: 0
      field :failed_count, :integer, default: 0
      field :metadata, :map, default: %{}
      field :error_message, :string

      belongs_to :user, Streamsync.Accounts.User

      timestamps(type: :utc_datetime)
    end

    def changeset(job, attrs) do
      job
      |> cast(attrs, [
        :from_provider,
        :to_provider,
        :status,
        :song_count,
        :sync_type,
        :synced_count,
        :failed_count,
        :metadata,
        :error_message,
        :user_id
      ])
      |> validate_required([
        :from_provider,
        :to_provider,
        :status,
        :sync_type,
        :song_count,
        :user_id
      ])
      |> validate_inclusion(:from_provider, @valid_providers)
      |> validate_inclusion(:to_provider, @valid_providers)
      |> validate_number(:song_count, greater_than: 0)
    end
  end

  @doc """
  Creates a sync job and queues the Oban job to process it.
  """
  def create_sync_job(_user, %{source_provider_ids: []}), do: {:error, :empty_job}

  def create_sync_job(user, %{sync_type: "playlists"} = attrs) do
    playlists = Map.get(attrs, :source_provider_ids)

    job_attrs =
      Map.merge(attrs, %{
        user_id: user.id,
        status: :pending,
        song_count: length(playlists)
      })

    Repo.transact(fn ->
      with {:ok, sync_job} <- %Job{} |> Job.changeset(job_attrs) |> Repo.insert(),
           _oban_jobs <- bulk_queue_sync_jobs(user, sync_job, attrs[:source_provider_ids]) do
        {:ok, sync_job}
      end
    end)
  end

  def create_sync_job(user, attrs) do
    job_attrs =
      Map.merge(attrs, %{
        user_id: user.id,
        status: :pending,
        song_count: length(attrs[:source_provider_ids] || [])
      })

    with {:ok, sync_job} <- %Job{} |> Job.changeset(job_attrs) |> Repo.insert(),
         {:ok, _oban_job} <- queue_sync_job(user, sync_job, attrs[:source_provider_ids] || []) do
      {:ok, sync_job}
    end
  end

  @doc """
  Gets a sync job by ID.
  """
  def get_sync_job!(id), do: Repo.get!(Job, id)

  @doc """
  Lists all sync jobs for a user.
  """
  def list_sync_jobs(user) do
    from(j in Job, where: j.user_id == ^user.id, order_by: [desc: j.inserted_at])
    |> Repo.all()
  end

  @doc """
  Updates the status of a sync job.
  """
  def update_sync_job_status(job_id, status, metadata \\ %{}) do
    job = get_sync_job!(job_id)

    attrs = %{
      status: status,
      metadata: metadata
    }

    # Add specific fields based on metadata
    attrs =
      attrs
      |> maybe_add_counts(metadata)
      |> maybe_add_error(metadata)

    job
    |> Job.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets sync jobs with optional filtering.
  """
  def get_sync_jobs(user, opts \\ []) do
    query = from(j in Job, where: j.user_id == ^user.id)

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> from(j in query, where: j.status == ^status)
      end

    query
    |> order_by([j], desc: j.inserted_at)
    |> Repo.all()
  end

  # Private functions

  defp queue_sync_job(user, sync_job, song_ids) do
    SyncJob.new(%{
      user_id: user.id,
      from_provider: sync_job.from_provider,
      to_provider: sync_job.to_provider,
      sync_type: sync_job.sync_type,
      song_ids: song_ids,
      sync_job_id: sync_job.id
    })
    |> Oban.insert()
  end

  defp bulk_queue_sync_jobs(user, sync_job, ids) do
    Enum.map(ids, fn id ->
      SyncJob.new(%{
        user_id: user.id,
        from_provider: sync_job.from_provider,
        to_provider: sync_job.to_provider,
        sync_type: sync_job.sync_type,
        source_provider_ids: [id],
        sync_job_id: sync_job.id
      })
    end)
    |> Oban.insert_all()
  end

  defp maybe_add_counts(attrs, %{synced_count: synced_count, failed_count: failed_count}) do
    attrs
    |> Map.put(:synced_count, synced_count)
    |> Map.put(:failed_count, failed_count)
  end

  defp maybe_add_counts(attrs, _metadata), do: attrs

  defp maybe_add_error(attrs, %{error: error}) do
    Map.put(attrs, :error_message, to_string(error))
  end

  defp maybe_add_error(attrs, _metadata), do: attrs
end
