defmodule EphemeralChatWeb.MessageComponent do
  use EphemeralChatWeb, :live_component

  @impl true
  def mount(socket) do
    if connected?(socket) do
      :timer.send_interval(1000, self(), :tick)
    end

    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    time_remaining = max(0, DateTime.diff(assigns.message.expires_at, DateTime.utc_now()))
    {:ok, assign(socket, assigns |> Map.put(:time_remaining, time_remaining))}
  end

  @impl true
  def handle_event("tick", _params, socket) do
    time_remaining = max(0, DateTime.diff(socket.assigns.message.expires_at, DateTime.utc_now()))
    {:noreply, assign(socket, :time_remaining, time_remaining)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="message-item animate-appear" id={"message-#{@message.id}"}>
      <div class={"rounded-lg p-3 max-w-3xl #{if @message.username == @current_user.username, do: "ml-auto bg-blue-100 text-blue-800", else: "mr-auto bg-gray-100 text-gray-800"}"}>
        <div class="flex items-start justify-between gap-2">
          <div class="flex flex-col">
            <span class="font-semibold">
              {@message.username}
            </span>
            <span class="text-xs text-gray-500">
              {Calendar.strftime(@message.inserted_at, "%I:%M %p")}
            </span>
          </div>

          <div class="countdown-timer text-xs font-mono text-red-500">
            {@time_remaining}s
          </div>
        </div>

        <p class="mt-1">{@message.content}</p>
      </div>
    </div>
    """
  end
end
