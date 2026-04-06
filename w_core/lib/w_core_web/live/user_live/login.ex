defmodule WCoreWeb.UserLive.Login do
  @moduledoc """
  Redirect-only login LiveView.

  Keeps `/users/log-in` compatible while forwarding users to the unified
  registration/authentication entry point.
  """

  use WCoreWeb, :live_view

  @impl true
  @doc "Redirects all login traffic to the registration route."
  @spec mount(term(), term(), term()) :: term()
  def mount(_params, _session, socket) do
    {:ok, redirect(socket, to: ~p"/users/register")}
  end

  @impl true
  @doc "Renders a fallback message while redirecting to registration."
  @spec render(term()) :: term()
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      page_title="Authentication"
      page_subtitle="Redirecting to registration"
      content_max_width="max-w-lg"
    >
      <div class="rounded-xl border border-zinc-200 bg-white p-5 text-sm text-zinc-700 shadow-sm dark:border-zinc-800 dark:bg-zinc-900 dark:text-zinc-200">
        <p>Redirecting to the registration page.</p>
        <p class="mt-1">
          If nothing happens, continue in
          <.link navigate={~p"/users/register"} class="font-semibold text-brand hover:underline">
            Create account
          </.link>.
        </p>
      </div>
    </Layouts.app>
    """
  end
end
