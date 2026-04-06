defmodule WCoreWeb.PageController do
  use WCoreWeb, :controller

  @spec home(term(), term()) :: term()
  def home(conn, _params) do
    if conn.assigns.current_scope && conn.assigns.current_scope.user do
      redirect(conn, to: ~p"/control-room")
    else
      redirect(conn, to: ~p"/users/log-in")
    end
  end
end
