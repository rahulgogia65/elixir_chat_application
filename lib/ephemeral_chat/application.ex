defmodule EphemeralChat.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EphemeralChatWeb.Telemetry,
      EphemeralChat.Repo,
      {DNSCluster, query: Application.get_env(:ephemeral_chat, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: EphemeralChat.PubSub},
      EphemeralChatWeb.Presence,
      # Start the Finch HTTP client for sending emails
      {Finch, name: EphemeralChat.Finch},
      # Start periodic tasks
      EphemeralChat.PeriodicTasks,
      # Start to serve requests, typically the last entry
      EphemeralChatWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: EphemeralChat.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EphemeralChatWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
