defmodule StreamsyncWeb.SyncLive.Index do
  use StreamsyncWeb, :live_view

  alias Streamsync.Sync

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to job updates for real-time notifications
    Phoenix.PubSub.subscribe(Streamsync.PubSub, "sync_jobs:#{socket.assigns.current_user.id}")

    # Get actual sync jobs for this user
    jobs = Sync.list_sync_jobs(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Sync Jobs")
     |> stream(:jobs, jobs)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Sync Jobs")
    |> assign(:job, nil)
  end

  @impl true
  def handle_info({:sync_job_updated, job_id, status}, socket) do
    # Handle real-time job updates via PubSub
    updated_job = Sync.get_sync_job!(job_id)

    {:noreply, stream_insert(socket, :jobs, updated_job, at: 0)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    job = Sync.get_sync_job!(id)

    # For now, we don't actually delete jobs, just mark them as cancelled
    case Sync.update_sync_job_status(job.id, :failed, %{error: "Cancelled by user"}) do
      {:ok, updated_job} ->
        {:noreply, stream_insert(socket, :jobs, updated_job)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel job")}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    # Refresh the job list
    jobs = Sync.list_sync_jobs(socket.assigns.current_user)

    {:noreply, stream(:jobs, jobs, reset: true)}
  end

  # Helper functions for the template
  def format_status(:pending), do: "Pending"
  def format_status(:processing), do: "Processing"
  def format_status(:completed), do: "Completed"
  def format_status(:failed), do: "Failed"

  def status_color(:pending), do: "text-yellow-600"
  def status_color(:processing), do: "text-blue-600"
  def status_color(:completed), do: "text-green-600"
  def status_color(:failed), do: "text-red-600"

  def format_providers(from_provider, to_provider) do
    "#{String.capitalize(from_provider)} → #{String.capitalize(to_provider)}"
  end

  def format_progress(job) do
    total = job.song_count
    synced = job.synced_count || 0
    failed = job.failed_count || 0

    case job.status do
      :pending -> "#{total} songs queued"
      :processing -> "#{synced}/#{total} synced"
      :completed -> "#{synced}/#{total} synced, #{failed} failed"
      :failed -> "Failed: #{job.error_message || "Unknown error"}"
    end
  end
end
