defmodule EphemeralChatWeb.Presence do
  use Phoenix.Presence,
    otp_app: :ephemeral_chat,
    pubsub_server: EphemeralChat.PubSub
end
