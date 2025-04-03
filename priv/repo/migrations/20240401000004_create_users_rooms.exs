defmodule EphemeralChat.Repo.Migrations.CreateUsersRooms do
  use Ecto.Migration

  def change do
    create table(:users_rooms, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :room_id, references(:rooms, type: :binary_id, on_delete: :delete_all), null: false
    end

    create unique_index(:users_rooms, [:user_id, :room_id])
    create index(:users_rooms, [:room_id])
  end
end
