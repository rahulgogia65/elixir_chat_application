defmodule EphemeralChat.Chat.UserRoom do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "users_rooms" do
    belongs_to :user, EphemeralChat.Users.User, type: :binary_id
    belongs_to :room, EphemeralChat.Chat.Room, type: :binary_id
  end

  def changeset(user_room, attrs) do
    user_room
    |> cast(attrs, [:user_id, :room_id])
    |> validate_required([:user_id, :room_id])
    |> unique_constraint([:user_id, :room_id], name: :users_rooms_user_id_room_id_index)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:room_id)
  end
end
