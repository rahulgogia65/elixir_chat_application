defmodule EphemeralChat.Repo.Migrations.CreateRooms do
  use Ecto.Migration

  def change do
    create table(:rooms, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code, :string, null: false
      add :name, :string, null: false
      add :created_by, :string, null: false
      add :passcode, :string
      add :message_ttl, :integer, default: 300
      add :last_activity, :utc_datetime, null: false
      add :is_private, :boolean, default: false

      timestamps()
    end

    create unique_index(:rooms, [:code])
  end
end
