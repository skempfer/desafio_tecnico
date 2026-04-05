defmodule WCoreWeb.TelemetryComponents do
  use Phoenix.Component

  @moduledoc """
  LiveView components for telemetry dashboard.
  """

  attr :status, :string, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={badge_class(@status)}>
      {@status}
    </span>
    """
  end

  defp badge_class("online"), do: "px-2 py-1 rounded text-xs bg-green-100 text-green-800"
  defp badge_class("degraded"), do: "px-2 py-1 rounded text-xs bg-amber-100 text-amber-800"
  defp badge_class("offline"), do: "px-2 py-1 rounded text-xs bg-red-100 text-red-800"
  defp badge_class(_), do: "px-2 py-1 rounded text-xs bg-zinc-100 text-zinc-700"
end
