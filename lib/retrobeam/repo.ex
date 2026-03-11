defmodule Retrobeam.Repo do
  use Ecto.Repo,
    otp_app: :retrobeam,
    adapter: Ecto.Adapters.Postgres
end
