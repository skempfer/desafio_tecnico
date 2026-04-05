defmodule WCoreWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use WCoreWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :page_title, :string, default: nil, doc: "optional page title shown in the app header"
  attr :page_subtitle, :string, default: nil, doc: "optional subtitle shown below the page title"

  slot :inner_block, required: true

  @spec app(term()) :: term()
  def app(assigns) do
    ~H"""
    <header class="border-b border-zinc-200 px-4 sm:px-6 lg:px-8 dark:border-zinc-800">
      <div class="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-4 py-3">
        <div>
          <h1 :if={@page_title} class="text-lg font-semibold text-zinc-900 dark:text-zinc-100">
            {@page_title}
          </h1>
          <p :if={@page_subtitle} class="text-sm text-zinc-500 dark:text-zinc-400">
            {@page_subtitle}
          </p>
        </div>
        <div class="flex items-center gap-2 sm:gap-3">
          <%= if @current_scope && @current_scope.user do %>
            <span class="hidden truncate text-sm text-zinc-500 dark:text-zinc-400 sm:block max-w-[200px]">
              {@current_scope.user.email}
            </span>
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="rounded-md px-3 py-1.5 text-sm font-medium text-zinc-700 hover:bg-zinc-100 hover:text-zinc-900 dark:text-zinc-300 dark:hover:bg-zinc-800 dark:hover:text-white"
            >
              Log out
            </.link>
          <% end %>
          <.theme_toggle current_scope={@current_scope} />
        </div>
      </div>
    </header>

    <main class="px-4 pb-12 pt-6 sm:px-6 sm:pb-14 sm:pt-10 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  @spec flash_group(term()) :: term()
  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides a theme toggle with sun/moon/system icons and active state highlight.
  Optionally renders a settings gear icon when current_scope has a user.
  """
  attr :current_scope, :map, default: nil

  @spec theme_toggle(term()) :: term()
  def theme_toggle(assigns) do
    ~H"""
    <div
      id="theme-toggle"
      phx-hook="ThemeToggle"
      class="flex items-center gap-0.5 rounded-full border border-zinc-300 bg-zinc-100 p-1 dark:border-zinc-700 dark:bg-zinc-800"
    >
      <.link
        :if={@current_scope && @current_scope.user}
        href={~p"/users/settings"}
        title="Settings"
        aria-label="Settings"
        class="rounded-full p-1.5 text-zinc-500 transition-colors hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-white"
      >
        <.icon name="hero-cog-6-tooth" class="size-4" />
      </.link>

      <span :if={@current_scope && @current_scope.user} class="w-px self-stretch bg-zinc-300 dark:bg-zinc-600 mx-0.5"></span>

      <button
        data-theme-btn="system"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        title="System"
        type="button"
        aria-label="System theme"
        class="rounded-full p-1.5 text-zinc-500 transition-colors hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-white"
      >
        <.icon name="hero-computer-desktop" class="size-4" />
      </button>

      <button
        data-theme-btn="light"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        title="Light"
        type="button"
        aria-label="Light theme"
        class="rounded-full p-1.5 text-zinc-500 transition-colors hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-white"
      >
        <.icon name="hero-sun" class="size-4" />
      </button>

      <button
        data-theme-btn="dark"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        title="Dark"
        type="button"
        aria-label="Dark theme"
        class="rounded-full p-1.5 text-zinc-500 transition-colors hover:text-zinc-900 dark:text-zinc-400 dark:hover:text-white"
      >
        <.icon name="hero-moon" class="size-4" />
      </button>
    </div>
    """
  end
end
