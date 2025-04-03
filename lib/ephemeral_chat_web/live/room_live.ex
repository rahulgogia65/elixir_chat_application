defmodule EphemeralChatWeb.RoomLive do
  use EphemeralChatWeb, :live_view

  alias EphemeralChat.{Users, Chat}

  @impl true
  def mount(%{"code" => room_code}, %{"user_token" => token} = _session, socket) do
    case Users.get_user_by_session_token(token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Session expired. Please login again.")
         |> redirect(to: ~p"/")}

      user ->
        if Users.session_active?(user) do
          room = Chat.get_room_by_code(room_code)

          if is_nil(room) do
            {:ok,
             socket
             |> put_flash(:error, "Room not found.")
             |> redirect(to: ~p"/chat")}
          else
            # Ensure user is in the room
            unless Chat.user_in_room?(user.id, room.id) do
              Chat.add_user_to_room(user.id, room.id)
            end

            # Touch timestamps
            Users.touch_user(user.id)
            Chat.touch_room(room.id)

            # Setup Phoenix Channel connection and presence tracking if connected
            presence_active_users =
              if connected?(socket) do
                EphemeralChatWeb.Endpoint.subscribe("room:#{room_code}")

                # Track presence
                {:ok, _} =
                  EphemeralChatWeb.Presence.track(
                    self(),
                    "room:#{room_code}",
                    user.id,
                    %{username: user.username, joined_at: :os.system_time(:second)}
                  )

                # Get initial presence state
                presence_active_users =
                  "room:#{room_code}"
                  |> EphemeralChatWeb.Presence.list()
                  |> Map.values()
                  |> Enum.map(fn %{metas: [meta | _]} -> %{username: meta.username} end)
                  |> Enum.uniq_by(& &1.username)


                # Dispatch join room event to initialize socket connection
                push_event(socket, "join-room", %{
                  room: room_code,
                  token: token
                })

                presence_active_users
              end

            # Get initial messages
            messages = Chat.list_room_messages(room.id)

            # Start timer for message expiration
            if connected?(socket) do
              :timer.send_interval(1000, self(), :check_expired_messages)
            end

            {:ok,
             socket
             |> assign(:user, user)
             |> assign(:room, room)
             |> assign(:active_users, presence_active_users || [])
             |> assign(:typing_users, [])
             |> assign(:message_form, to_form(%{"content" => ""}))
             |> stream(
               :messages,
               transform_messages(messages)
             )}
          end
        else
          {:ok,
           socket
           |> put_flash(:error, "Session expired. Please login again.")
           |> redirect(to: ~p"/")}
        end
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> put_flash(:error, "Please login first.")
     |> redirect(to: ~p"/")}
  end

  @impl true
  def handle_event("send_message", %{"content" => content}, socket) when content != "" do
    # Create message through Chat context
    case Chat.create_message(socket.assigns.room.id, socket.assigns.user.id, %{content: content}) do
      {:ok, message} ->
        # Broadcast message to all users in the room
        EphemeralChatWeb.Endpoint.broadcast(
          "room:#{socket.assigns.room.code}",
          "message:new",
          %{
            id: message.id,
            content: message.content,
            username: socket.assigns.user.username,
            expires_at: message.expires_at,
            time_remaining: max(0, DateTime.diff(message.expires_at, DateTime.utc_now())),
            inserted_at: message.inserted_at
          }
        )

        # Simply assign a new empty form
        {:noreply, assign(socket, :message_form, to_form(%{"content" => ""}))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to send message")}
    end
  end

  @impl true
  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("user_typing", _params, socket) do
    # Broadcast typing indicator
    EphemeralChatWeb.Endpoint.broadcast(
      "room:#{socket.assigns.room.code}",
      "user:typing",
      %{username: socket.assigns.user.username}
    )

    # Schedule a timer to clear the typing indicator after 3 seconds
    if connected?(socket) do
      Process.send_after(self(), {:clear_typing, socket.assigns.user.username}, 3000)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("user_stopped_typing", _params, socket) do
    # Broadcast stopped typing indicator
    EphemeralChatWeb.Endpoint.broadcast(
      "room:#{socket.assigns.room.code}",
      "user:stopped_typing",
      %{username: socket.assigns.user.username}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("leave_room", _params, socket) do
    room = socket.assigns.room
    user = socket.assigns.user

    # Remove user from room
    Chat.remove_user_from_room(user.id, room.id)

    {:noreply,
     socket
     |> put_flash(:info, "Left room #{room.name}")
     |> push_navigate(to: ~p"/chat")}
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    message_data = %{
      id: message.id,
      content: message.content,
      username: message.user.username,
      expires_at: message.expires_at,
      time_remaining: max(0, DateTime.diff(message.expires_at, DateTime.utc_now())),
      inserted_at: message.inserted_at
    }

    {:noreply, stream_insert(socket, :messages, message_data)}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff}, socket) do
    # Get updated active users list from presence diff
    current_users = socket.assigns.active_users
    leaves = Map.values(diff.leaves) |> Enum.map(fn %{metas: [meta | _]} -> meta.username end)
    joins = Map.values(diff.joins) |> Enum.map(fn %{metas: [meta | _]} -> %{username: meta.username} end)

    # Remove users who left and add users who joined
    updated_users =
      current_users
      |> Enum.reject(fn user -> user.username in leaves end)
      |> Enum.concat(joins)
      |> Enum.uniq_by(& &1.username)

    {:noreply, assign(socket, :active_users, updated_users)}
  end

  @impl true
  def handle_info(%{event: "presence:state", payload: %{users: users}}, socket) do
    # Update active users list from presence state
    active_users =
      Map.values(users)
      |> Enum.map(fn %{metas: [meta | _]} -> %{username: meta.username} end)
      |> Enum.uniq_by(& &1.username)

    {:noreply, assign(socket, :active_users, active_users)}
  end

  @impl true
  def handle_info(%{event: "messages:list", payload: %{messages: messages}}, socket) do
    # Sort messages by timestamp
    sorted_messages = Enum.sort_by(messages, fn m -> m.inserted_at end)

    {:noreply, assign(socket, :messages, sorted_messages)}
  end

  @impl true
  def handle_info(%{event: "message:new", payload: message}, socket) do
    message_data = %{
      id: message.id,
      content: message.content,
      username: message.username,
      expires_at: message.expires_at,
      time_remaining: max(0, DateTime.diff(message.expires_at, DateTime.utc_now())),
      inserted_at: message.inserted_at
    }

    {:noreply, stream_insert(socket, :messages, message_data)}
  end

  @impl true
  def handle_info(%{event: "user:typing", payload: %{username: username}}, socket) do
    user = socket.assigns.user

    # Don't show typing indicator for the current user
    if username != user.username do
      typing_users = socket.assigns.typing_users

      updated_typing_users =
        if username in typing_users do
          typing_users
        else
          [username | typing_users]
        end

      {:noreply, assign(socket, :typing_users, updated_typing_users)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%{event: "user:stopped_typing", payload: %{username: username}}, socket) do
    typing_users = socket.assigns.typing_users
    updated_typing_users = Enum.reject(typing_users, fn u -> u == username end)

    {:noreply, assign(socket, :typing_users, updated_typing_users)}
  end

  @impl true
  def handle_info(:check_expired_messages, socket) do
    # Get active messages from database instead of stream
    messages = Chat.list_active_messages(socket.assigns.room.id)

    # Reset the stream with current active messages
    {:noreply, stream(socket, :messages, transform_messages(messages), reset: true)}
  end

  @impl true
  def handle_info(:tick, socket) do
    # Get active messages from database
    messages = Chat.list_active_messages(socket.assigns.room.id)

    # Reset the stream with updated time_remaining values
    {:noreply, stream(socket, :messages, transform_messages(messages), reset: true)}
  end

  @impl true
  def handle_info({:clear_typing, username}, socket) do
    # Broadcast stopped typing
    EphemeralChatWeb.Endpoint.broadcast(
      "room:#{socket.assigns.room.code}",
      "user:stopped_typing",
      %{username: username}
    )

    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if Map.has_key?(socket.assigns, :room) do
      room = socket.assigns.room
      user = socket.assigns.user

      # Leave room
      Chat.remove_user_from_room(user.id, room.id)

      if connected?(socket) do
        EphemeralChatWeb.Endpoint.unsubscribe("room:#{room.code}")
      end
    end

    :ok
  end

  # Private function to transform messages into the format expected by the stream
  defp transform_messages(messages) do
    Enum.map(messages, fn msg ->
      %{
        id: msg.id,
        content: msg.content,
        username: msg.user.username,
        expires_at: msg.expires_at,
        time_remaining: max(0, DateTime.diff(msg.expires_at, DateTime.utc_now())),
        inserted_at: msg.inserted_at
      }
    end)
  end
end
