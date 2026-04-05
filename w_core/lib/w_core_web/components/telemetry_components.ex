defmodule WCoreWeb.TelemetryComponents do
  use Phoenix.Component

  @moduledoc """
  LiveView components for telemetry dashboard.
  """

  attr :status, :string, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={badge_class(@status)}>
      {String.upcase(@status)}
    </span>
    """
  end

  defp badge_class("online") do
    "inline-flex items-center rounded-full border border-emerald-200 bg-emerald-50 px-2.5 py-1 text-xs font-semibold tracking-wide text-emerald-800 dark:border-emerald-700/60 dark:bg-emerald-900/30 dark:text-emerald-300"
  end

  defp badge_class("degraded") do
    "inline-flex items-center rounded-full border border-amber-200 bg-amber-50 px-2.5 py-1 text-xs font-semibold tracking-wide text-amber-800 dark:border-amber-700/60 dark:bg-amber-900/30 dark:text-amber-300"
  end

  defp badge_class("offline") do
    "inline-flex items-center rounded-full border border-rose-200 bg-rose-50 px-2.5 py-1 text-xs font-semibold tracking-wide text-rose-800 dark:border-rose-700/60 dark:bg-rose-900/30 dark:text-rose-300"
  end

  defp badge_class(_) do
    "inline-flex items-center rounded-full border border-zinc-200 bg-zinc-50 px-2.5 py-1 text-xs font-semibold tracking-wide text-zinc-700 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-300"
  end
end
