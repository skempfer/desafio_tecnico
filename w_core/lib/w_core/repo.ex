defmodule WCore.Repo do
  @moduledoc """
  Ecto repository for WCore.

  Provides database access using the SQLite3 adapter.
  """

  use Ecto.Repo,
    otp_app: :w_core,
    adapter: Ecto.Adapters.SQLite3
end
