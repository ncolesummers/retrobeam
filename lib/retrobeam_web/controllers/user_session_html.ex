defmodule RetrobeamWeb.UserSessionHTML do
  use RetrobeamWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:retrobeam, Retrobeam.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
