defmodule EphemeralChat.Users do
  @moduledoc """
  The Users context manages temporary anonymous users.
  """

  import Ecto.Query, warn: false
  alias EphemeralChat.Repo
  alias EphemeralChat.Users.User

  # 30 minutes
  @inactive_timeout_seconds 30 * 60

  @doc """
  Creates a new anonymous user with a random username.
  """
  def create_anonymous_user(ip_address) do
    username = generate_unique_username()
    session_token = User.generate_session_token()

    %User{}
    |> User.changeset(%{
      username: username,
      session_token: session_token,
      last_activity: DateTime.utc_now(),
      ip_address: ip_address
    })
    |> Repo.insert()
  end

  @doc """
  Updates a user's last activity timestamp.
  """
  def touch_user(user_id) do
    from(u in User, where: u.id == ^user_id)
    |> Repo.update_all(set: [last_activity: DateTime.utc_now()])
  end

  @doc """
  Gets a user by their session token.
  """
  def get_user_by_session_token(token) do
    Repo.get_by(User, session_token: token)
  end

  @doc """
  Check if a user session is still valid based on the inactive timeout.
  """
  def session_active?(user) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, user.last_activity, :second)
    diff < @inactive_timeout_seconds
  end

  @doc """
  Returns users that are active in a specific room.
  """
  def list_active_users_in_room(room_id) when is_binary(room_id) do
    room_id = Ecto.UUID.dump!(room_id)
    inactive_cutoff = DateTime.add(DateTime.utc_now(), -@inactive_timeout_seconds, :second)

    query =
      from u in User,
        join: ur in "users_rooms",
        on: ur.user_id == u.id,
        where: ur.room_id == ^room_id and u.last_activity > ^inactive_cutoff,
        select: u

    Repo.all(query)
  end

  @doc """
  Cleans up inactive users (30+ minutes of inactivity).
  Should be run periodically via a scheduled job.
  """
  def cleanup_inactive_users do
    inactive_cutoff = DateTime.add(DateTime.utc_now(), -@inactive_timeout_seconds, :second)

    from(u in User, where: u.last_activity < ^inactive_cutoff)
    |> Repo.delete_all()
  end

  defp generate_unique_username do
    username = User.generate_username()

    if username_exists?(username) do
      generate_unique_username()
    else
      username
    end
  end

  defp username_exists?(username) do
    Repo.exists?(from u in User, where: u.username == ^username)
  end
end
