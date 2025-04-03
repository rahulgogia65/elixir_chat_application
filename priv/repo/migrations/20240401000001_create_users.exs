defmodule EphemeralChat.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :username, :string, null: false
      add :session_token, :string, null: false
      add :last_activity, :utc_datetime, null: false
      add :ip_address, :string

      timestamps()
    end

    create unique_index(:users, [:username])
    create unique_index(:users, [:session_token])
  end
end
