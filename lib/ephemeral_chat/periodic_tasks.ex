defmodule EphemeralChat.PeriodicTasks do
  @moduledoc """
  Handles periodic tasks like cleaning up inactive rooms and expired messages.
  """

  use GenServer
  require Logger

  # Run cleanup every 5 minutes
  @cleanup_interval :timer.minutes(5)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    Logger.info("Running periodic cleanup tasks...")

    # Clean up inactive rooms
    EphemeralChat.Chat.cleanup_inactive_rooms()

    # Clean up expired messages
    EphemeralChat.Chat.cleanup_expired_messages()

    # Schedule next cleanup
    schedule_cleanup()

    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
