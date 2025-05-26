defmodule StreamsyncWeb.SyncLive.Index do
  use StreamsyncWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    # {:ok, stream(socket, :posts, Sync.get_jobs(socket.assigns.current_user))}
    {:ok, stream(socket, :jobs, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  #   defp apply_action(socket, :edit, %{"id" => id}) do
  #     socket
  #     |> assign(:page_title, "Edit Post")
  #     |> assign(:post, Blog.get_post!(id))
  #   end

  #   defp apply_action(socket, :new, _params) do
  #     socket
  #     |> assign(:page_title, "New Post")
  #     |> assign(:post, %Post{})
  #   end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Sync")
    |> assign(:job, nil)
  end

  #   @impl true
  #   def handle_info({StreamsyncWeb.PostLive.FormComponent, {:saved, post}}, socket) do
  #     {:noreply, stream_insert(socket, :posts, post)}
  #   end

  #   @impl true
  #   def handle_event("delete", %{"id" => id}, socket) do
  #     post = Blog.get_post!(id)
  #     {:ok, _} = Blog.delete_post(post)

  #     {:noreply, stream_delete(socket, :posts, post)}
  #   end
end
