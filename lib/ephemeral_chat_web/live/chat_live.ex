defmodule EphemeralChatWeb.ChatLive do
  use EphemeralChatWeb, :live_view

  alias EphemeralChat.{Users, Chat}

  @impl true
  def mount(_params, %{"user_token" => token} = _session, socket) do
    case Users.get_user_by_session_token(token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Session expired. Please login again.")
         |> redirect(to: ~p"/")}

      user ->
        if Users.session_active?(user) do
          Users.touch_user(user.id)

          {:ok,
           socket
           |> assign(:user, user)
           |> assign(:current_room, nil)
           |> assign(:create_room_form, to_form(%{"message_ttl" => "300"}))}
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
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Chat Lobby")
    |> assign(:room_form, to_form(%{"code" => ""}))
  end

  @impl true
  def handle_event("create_room", %{"name" => name, "message_ttl" => message_ttl}, socket) do
    user = socket.assigns.user

    if Chat.can_create_room?(user.ip_address) do
      case Chat.create_room(
             %{
               name: name,
               created_by: user.username,
               last_activity: DateTime.utc_now(),
               message_ttl: String.to_integer(message_ttl)
             },
             user.id
           ) do
        {:ok, room} ->
          {:noreply,
           socket
           |> put_flash(:info, "Room created successfully! Share code: #{room.code}")
           |> push_navigate(to: ~p"/chat/room/#{room.code}")}

        {:error, _changeset} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to create room. Please try again.")}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Rate limit exceeded. Please try again later.")}
    end
  end

  @impl true
  def handle_event("join_room", %{"code" => code}, socket) do
    user = socket.assigns.user

    case Chat.join_room(code, user.id) do
      {:ok, room} ->
        {:noreply,
         socket
         |> push_navigate(to: ~p"/chat/room/#{room.code}")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Room not found.")}

      {:error, :invalid_passcode} ->
        {:noreply,
         socket
         |> put_flash(:error, "Invalid passcode for private room.")}
    end
  end
end
