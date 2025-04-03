defmodule EphemeralChatWeb.AuthController do
  use EphemeralChatWeb, :controller

  alias EphemeralChat.Users

  def login(conn, _params) do
    # Get the user's IP address
    ip_address = conn.remote_ip |> :inet.ntoa() |> to_string()

    # Create anonymous user
    case Users.create_anonymous_user(ip_address) do
      {:ok, user} ->
        conn
        |> put_session(:user_token, user.session_token)
        |> redirect(to: ~p"/chat")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Could not create anonymous user. Please try again.")
        |> redirect(to: ~p"/")
    end
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: ~p"/")
  end
end
