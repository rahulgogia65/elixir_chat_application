defmodule EphemeralChatWeb.RoomChannel do
  use Phoenix.Channel

  alias EphemeralChat.{Repo, Chat, Users}
  alias EphemeralChat.Users.User
  alias EphemeralChat.Chat.Message

  # User typing indicator state
  # ms
  @typing_timeout 3000

  # Join a room
  def join("room:" <> room_code, _params, socket) do
    user_id = socket.assigns.user_id

    case Chat.get_room_by_code(room_code) do
      nil ->
        {:error, %{reason: "Room not found"}}

      room ->
        if Chat.user_in_room?(user_id, room.id) do
          # Send current active users and messages
          send(self(), :after_join)

          {:ok,
           %{
             room_id: room.id,
             room_code: room.code,
             room_name: room.name,
             message_ttl: room.message_ttl
           }, assign(socket, %{room_id: room.id, room_code: room_code})}
        else
          {:error, %{reason: "Not a member of this room"}}
        end
    end
  end

  # Handle user joining a room
  def handle_info(:after_join, socket) do
    room_id = socket.assigns.room_id
    user_id = socket.assigns.user_id

    # Update user's last activity
    Users.touch_user(user_id)

    # Get current user
    user = Repo.get(User, user_id)

    # Broadcast user joined
    broadcast!(socket, "user:joined", %{
      username: user.username,
      timestamp: DateTime.utc_now()
    })

    # Push active users list
    active_users =
      Users.list_active_users_in_room(room_id)
      |> Enum.map(fn user -> %{username: user.username} end)

    push(socket, "presence:list", %{users: active_users})

    # Push active messages
    messages =
      Chat.list_active_messages(room_id)
      |> Enum.map(fn message ->
        %{
          id: message.id,
          content: message.content,
          username: message.user.username,
          inserted_at: message.inserted_at,
          expires_at: message.expires_at,
          time_remaining: Message.seconds_until_expiration(message)
        }
      end)

    push(socket, "messages:list", %{messages: messages})

    {:noreply, socket}
  end

  # Handle user stopped typing
  def handle_info({:user_stopped_typing, username}, socket) do
    broadcast!(socket, "user:stopped_typing", %{
      username: username
    })

    {:noreply, socket}
  end

  # Handle new chat message
  def handle_in("message:new", %{"content" => content}, socket) do
    room_id = socket.assigns.room_id
    user_id = socket.assigns.user_id

    case Chat.create_message(room_id, user_id, %{content: content}) do
      {:ok, message} ->
        user = Repo.get(User, user_id)

        # Broadcast message to everyone in the room
        broadcast!(socket, "message:new", %{
          id: message.id,
          content: message.content,
          username: user.username,
          inserted_at: message.inserted_at,
          expires_at: message.expires_at,
          time_remaining: Message.seconds_until_expiration(message)
        })

        {:reply, :ok, socket}

      {:error, _reason} ->
        {:reply, {:error, %{reason: "Failed to create message"}}, socket}
    end
  end

  # Handle user typing indicator
  def handle_in("user:typing", _params, socket) do
    user_id = socket.assigns.user_id
    user = Repo.get(User, user_id)

    # Broadcast typing event
    broadcast!(socket, "user:typing", %{
      username: user.username
    })

    # Schedule event to clear typing state
    Process.send_after(self(), {:user_stopped_typing, user.username}, @typing_timeout)

    {:reply, :ok, socket}
  end

  # Handle user leaving the channel
  def terminate(_reason, socket) do
    user_id = socket.assigns.user_id
    user = Repo.get(User, user_id)
    room_id = socket.assigns.room_id

    if user do
      # Remove user from room
      Chat.remove_user_from_room(user_id, room_id)

      # Broadcast user left event
      broadcast!(socket, "user:left", %{
        username: user.username,
        timestamp: DateTime.utc_now()
      })

      # Push updated active users list
      active_users =
        Users.list_active_users_in_room(room_id)
        |> Enum.map(fn user -> %{username: user.username} end)

      push(socket, "presence:list", %{users: active_users})
    end

    :ok
  end
end
