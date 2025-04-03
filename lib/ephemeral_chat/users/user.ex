defmodule EphemeralChat.Users.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "users" do
    field :username, :string
    field :session_token, :string
    field :last_activity, :utc_datetime
    field :ip_address, :string

    has_many :messages, EphemeralChat.Chat.Message
    many_to_many :rooms, EphemeralChat.Chat.Room, join_through: "users_rooms"

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :session_token, :last_activity, :ip_address])
    |> validate_required([:username, :session_token, :last_activity])
    |> unique_constraint(:username)
    |> unique_constraint(:session_token)
  end

  def generate_username do
    adjectives =
      ~w(Ancient Brave Calm Daring Eager Fierce Gentle Happy Icy Jolly Kind Lively Mystic Noble Odd Proud Quick Rad Silent Tough Unique Vivid Wild Xenial Young Zealous)

    animals =
      ~w(Ant Bear Cat Dog Eagle Fox Giraffe Hawk Ibex Jaguar Koala Lion Moose Narwhal Owl Panda Quokka Rabbit Snake Tiger Unicorn Vulture Wolf Xerus Yak Zebra)

    "#{Enum.random(adjectives)}#{Enum.random(animals)}#{:rand.uniform(100)}"
  end

  def generate_session_token do
    :crypto.strong_rand_bytes(32) |> Base.encode64()
  end
end
