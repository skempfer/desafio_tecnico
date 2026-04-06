defmodule WCoreWeb.UserLive.Registration do
  use WCoreWeb, :live_view

  alias WCore.Accounts
  alias WCore.Accounts.User

  @impl true
  @spec render(term()) :: term()
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      page_title="Access"
      page_subtitle="Use your email to sign in or create an account"
      content_max_width="max-w-xl"
    >
      <section class="rounded-2xl border border-zinc-300 bg-white p-6 shadow-sm dark:border-zinc-800 dark:bg-zinc-900 sm:p-7">
        <div class="mb-6">
          <p class="text-xs font-semibold uppercase tracking-[0.16em] text-zinc-500 dark:text-zinc-400">
            WCore Control Room
          </p>
          <h2 class="mt-2 text-2xl font-semibold tracking-tight text-zinc-900 dark:text-zinc-100">
            Criar conta ou entrar
          </h2>
          <p class="mt-2 text-sm leading-6 text-zinc-600 dark:text-zinc-300">
            Fluxo unico: login e cadastro por email, com o mesmo padrao visual da dashboard.
          </p>
        </div>

        <div class="mb-6 grid grid-cols-2 gap-2">
          <.link
            navigate={~p"/users/log-in"}
            class="inline-flex items-center justify-center rounded-xl border border-zinc-300 bg-zinc-50 px-3 py-2 text-sm font-medium text-zinc-700 transition hover:border-zinc-400 hover:bg-zinc-100 hover:text-zinc-900 dark:border-zinc-700 dark:bg-zinc-800/60 dark:text-zinc-200 dark:hover:border-zinc-600 dark:hover:bg-zinc-800"
          >
            Entrar
          </.link>
          <.link
            navigate={~p"/users/register"}
            class="inline-flex items-center justify-center rounded-xl border border-indigo-500/35 bg-indigo-500/12 px-3 py-2 text-sm font-semibold text-indigo-700 transition hover:bg-indigo-500/20 dark:border-indigo-400/40 dark:bg-indigo-400/15 dark:text-indigo-200"
          >
            Cadastrar
          </.link>
        </div>

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate" class="space-y-4">
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            class="w-full rounded-xl border-2 border-zinc-300 bg-zinc-50 px-3 py-2.5 text-zinc-900 placeholder:text-zinc-500 shadow-sm transition focus:border-indigo-500 focus:bg-white focus:outline-none focus:ring-4 focus:ring-indigo-500/15 dark:border-zinc-600 dark:bg-zinc-950 dark:text-zinc-100 dark:placeholder:text-zinc-500 dark:focus:border-indigo-400 dark:focus:bg-zinc-900"
            error_class="border-rose-500 ring-rose-500/20"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />

          <.button
            phx-disable-with="Enviando link..."
            class="mt-1 w-full rounded-xl bg-indigo-600 px-4 py-2.5 text-sm font-semibold text-white shadow-md shadow-indigo-900/25 transition hover:bg-indigo-500 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-indigo-500/30"
          >
            Continuar
          </.button>

          <p class="text-center text-xs text-zinc-500 dark:text-zinc-400">
            Ao continuar, voce recebe um email com link seguro para acesso.
          </p>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  @spec mount(term(), term(), term()) :: term()
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: WCoreWeb.UserAuth.signed_in_path(socket))}
  end

  @spec mount(term(), term(), term()) :: term()
  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_email(%User{}, %{}, validate_unique: false)

    {:ok, assign_form(socket, changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  @spec handle_event(term(), term(), term()) :: term()
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           "An email was sent to #{user.email}, please access it to confirm your account."
         )
         |> push_navigate(to: ~p"/users/register")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_email(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
