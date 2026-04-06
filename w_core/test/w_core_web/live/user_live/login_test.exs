defmodule WCoreWeb.UserLive.LoginTest do
  use WCoreWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "login route" do
    test "redirects to registration", %{conn: conn} do
      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/users/log-in")
      assert to == ~p"/users/register"
    end

    test "redirects to registration for re-authentication access", %{conn: conn} do
      conn = log_in_user(conn, WCore.AccountsFixtures.user_fixture())

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/users/log-in")
      assert to == ~p"/users/register"
    end
  end
end
