defmodule WCoreWeb.PageController do
  use WCoreWeb, :controller

  @spec home(term(), term()) :: term()
  def home(conn, _params) do
    render(conn, :home)
  end
end
