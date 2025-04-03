defmodule EphemeralChat.Chat.Room do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "rooms" do
    field :code, :string
    field :name, :string
    field :created_by, :string
    field :passcode, :string
    # 5 minutes in seconds
    field :message_ttl, :integer, default: 300
    field :last_activity, :utc_datetime
    field :is_private, :boolean, default: false

    has_many :messages, EphemeralChat.Chat.Message
    many_to_many :users, EphemeralChat.Users.User, join_through: "users_rooms"

    timestamps()
  end

  def changeset(room, attrs) do
    room
    |> cast(attrs, [
      :code,
      :name,
      :created_by,
      :passcode,
      :message_ttl,
      :last_activity,
      :is_private
    ])
    |> validate_required([:code, :name, :created_by, :last_activity])
    |> validate_number(:message_ttl, greater_than_or_equal_to: 60, less_than_or_equal_to: 3600)
    |> unique_constraint(:code)
  end

  def generate_room_code do
    code = for _ <- 1..6, into: "", do: <<Enum.random(?A..?Z)>>
    code
  end
end
