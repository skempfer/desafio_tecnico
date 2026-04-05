defmodule WCore.TelemetryComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  import WCoreWeb.TelemetryComponents

  test "status_badge renders degraded variant" do
    html = render_component(&status_badge/1, status: "degraded")
    assert html =~ "DEGRADED"
    assert html =~ "amber"
  end
end
