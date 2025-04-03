defmodule EphemeralChat.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :content, :text, null: false
      add :expires_at, :utc_datetime, null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :room_id, references(:rooms, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:messages, [:user_id])
    create index(:messages, [:room_id])
    create index(:messages, [:expires_at])
  end
end
