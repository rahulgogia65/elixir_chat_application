defmodule EphemeralChatWeb.UserSocket do
  use Phoenix.Socket

  # Channels
  channel "room:*", EphemeralChatWeb.RoomChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case EphemeralChat.Users.get_user_by_session_token(token) do
      nil ->
        :error

      user ->
        case EphemeralChat.Users.session_active?(user) do
          true ->
            # Update last activity
            EphemeralChat.Users.touch_user(user.id)
            {:ok, assign(socket, :user_id, user.id)}

          false ->
            :error
        end
    end
  end

  @impl true
  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end
