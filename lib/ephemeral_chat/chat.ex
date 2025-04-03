defmodule EphemeralChat.Chat do
  @moduledoc """
  The Chat context manages ephemeral chat rooms and messages.
  """

  import Ecto.Query, warn: false
  alias EphemeralChat.Repo
  alias EphemeralChat.Chat.{Room, Message, UserRoom}
  alias EphemeralChat.Users.User

  # Rooms inactive for 24 hours will be deleted
  @room_inactive_timeout_seconds 24 * 60 * 60

  # Rate limiting: max 5 rooms per IP in a 10-minute window
  @max_rooms_per_ip 5
  # @rate_limit_window_seconds 10 * 60
  @rate_limit_window_seconds 10 * 60

  @doc """
  Creates a new chat room.
  """
  def create_room(attrs, user_id) do
    # Generate a unique room code
    room_code = generate_unique_room_code()

    %Room{}
    |> Room.changeset(
      Map.merge(attrs, %{
        code: room_code,
        last_activity: DateTime.utc_now()
      })
    )
    |> Repo.insert()
    |> case do
      {:ok, room} ->
        # Add the creator to the room
        add_user_to_room(user_id, room.id)
        {:ok, room}

      error ->
        error
    end
  end

  @doc """
  Checks if a user can create a new room based on rate limiting.
  """
  def can_create_room?(ip_address) do
    time_window = DateTime.add(DateTime.utc_now(), -@rate_limit_window_seconds, :second)

    query =
      from u in User,
        where: u.ip_address == ^ip_address and u.inserted_at > ^time_window,
        join: r in Room,
        on: r.created_by == u.username,
        select: count(r.id)

    count = Repo.one(query)
    count < @max_rooms_per_ip
  end

  @doc """
  Gets a room by its unique code.
  """
  def get_room_by_code(code) do
    Repo.get_by(Room, code: code)
  end

  @doc """
  Join a room by code (and optional passcode for private rooms).
  """
  def join_room(room_code, user_id, passcode \\ nil) do
    room = get_room_by_code(room_code)

    cond do
      is_nil(room) ->
        {:error, :not_found}

      room.is_private && room.passcode != passcode ->
        {:error, :invalid_passcode}

      true ->
        add_user_to_room(user_id, room.id)
        touch_room(room.id)
        {:ok, room}
    end
  end

  @doc """
  Updates a room's last activity timestamp.
  """
  def touch_room(room_id) do
    from(r in Room, where: r.id == ^room_id)
    |> Repo.update_all(set: [last_activity: DateTime.utc_now()])
  end

  @doc """
  Adds a user to a room.
  """
  def add_user_to_room(user_id, room_id) do
    with %User{} = user <- Repo.get(User, user_id),
         %Room{} = room <- Repo.get(Room, room_id) do
      %UserRoom{}
      |> UserRoom.changeset(%{user_id: user.id, room_id: room.id})
      |> Repo.insert(on_conflict: :nothing)
      |> case do
        {:ok, _} -> {:ok, true}
        {:error, changeset} -> {:error, changeset}
      end
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  Removes a user from a room.
  """
  def remove_user_from_room(user_id, room_id) do
    query =
      from ur in UserRoom,
        where: ur.user_id == ^user_id and ur.room_id == ^room_id

    Repo.delete_all(query)
  end

  @doc """
  Checks if a user is in a specific room.
  """
  def user_in_room?(user_id, room_id) do
    query =
      from r in Room,
        join: u in assoc(r, :users),
        where: r.id == ^room_id and u.id == ^user_id,
        select: count(r.id)

    count = Repo.one(query)
    count > 0
  rescue
    # If any error occurs (including UUID conversion issues), return false
    _ -> false
  end

  @doc """
  Lists all active rooms (with activity in the last 24 hours).
  """
  def list_active_rooms do
    inactive_cutoff = DateTime.add(DateTime.utc_now(), -@room_inactive_timeout_seconds, :second)

    from(r in Room, where: r.last_activity > ^inactive_cutoff)
    |> Repo.all()
  end

  @doc """
  Cleans up inactive rooms (no activity for 24+ hours).
  Should be run periodically via a scheduled job.
  """
  def cleanup_inactive_rooms do
    inactive_cutoff = DateTime.add(DateTime.utc_now(), -@room_inactive_timeout_seconds, :second)

    from(r in Room, where: r.last_activity < ^inactive_cutoff)
    |> Repo.delete_all()
  end

  defp generate_unique_room_code do
    code = Room.generate_room_code()

    if room_code_exists?(code) do
      generate_unique_room_code()
    else
      code
    end
  end

  defp room_code_exists?(code) do
    Repo.exists?(from r in Room, where: r.code == ^code)
  end

  # === Message Management ===

  @doc """
  Creates a new message in a room.
  """
  def create_message(room_id, user_id, attrs) do
    # Get the room to determine TTL
    room = Repo.get(Room, room_id)

    if room do
      # Calculate expiration time
      expires_at = Message.calculate_expiration_time(room.message_ttl)

      # Create the message
      %Message{}
      |> Message.changeset(
        Map.merge(attrs, %{
          room_id: room_id,
          user_id: user_id,
          expires_at: expires_at
        })
      )
      |> Repo.insert()
      |> case do
        {:ok, message} ->
          # Update room activity
          touch_room(room_id)
          {:ok, message}

        error ->
          error
      end
    else
      {:error, :room_not_found}
    end
  end

  @doc """
  Gets active messages in a room (not expired).
  """
  def list_active_messages(room_id) do
    now = DateTime.utc_now()

    query =
      from m in Message,
        where: m.room_id == ^room_id and m.expires_at > ^now,
        preload: [:user],
        order_by: [asc: m.inserted_at]

    Repo.all(query)
  end

  @doc """
  Deletes expired messages.
  Should be run periodically via a scheduled job.
  """
  def cleanup_expired_messages do
    now = DateTime.utc_now()

    from(m in Message, where: m.expires_at <= ^now)
    |> Repo.delete_all()
  end

  @doc """
  Lists all messages in a room, ordered by insertion time.
  """
  def list_room_messages(room_id) do
    Message
    |> where([m], m.room_id == ^room_id)
    |> order_by([m], asc: m.inserted_at)
    |> preload(:user)
    |> Repo.all()
  end
end
