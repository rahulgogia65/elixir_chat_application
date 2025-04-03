defmodule EphemeralChat.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "messages" do
    field :content, :string
    field :expires_at, :utc_datetime

    belongs_to :user, EphemeralChat.Users.User, type: :binary_id
    belongs_to :room, EphemeralChat.Chat.Room, type: :binary_id

    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:content, :expires_at, :user_id, :room_id])
    |> validate_required([:content, :expires_at, :user_id, :room_id])
  end

  @doc """
  Calculate the expiration time for a message based on room TTL settings.
  """
  def calculate_expiration_time(room_ttl) do
    DateTime.add(DateTime.utc_now(), room_ttl, :second)
  end

  @doc """
  Check if a message has expired.
  """
  def expired?(message) do
    DateTime.compare(DateTime.utc_now(), message.expires_at) != :lt
  end

  @doc """
  Calculate seconds remaining until expiration.
  """
  def seconds_until_expiration(message) do
    DateTime.diff(message.expires_at, DateTime.utc_now(), :second)
  end
end
