defmodule SymphonyElixirWeb.ProvidersLive do
  @moduledoc """
  Settings page for managing LLM provider credentials. Lists known providers,
  lets the user add new ones (presets + custom), refresh model lists, and
  delete entries. API keys are written to the macOS Keychain, never to the
  SQLite row.
  """

  use Phoenix.LiveView

  alias SymphonyElixir.{Control, Keychain, ProviderCatalog}
  alias SymphonyElixir.Control.Provider

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:providers, Control.list_providers())
     |> assign(:form, to_new_form())
     |> assign(:flash_message, nil)
     |> assign(:flash_kind, :info)}
  end

  @impl true
  def handle_event("change_kind", %{"provider" => %{"kind" => kind}}, socket) do
    preset = ProviderCatalog.preset(kind) || %{base_url: ""}
    form = socket.assigns.form |> Map.put("kind", kind) |> Map.put("base_url", preset.base_url)
    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"provider" => params}, socket) do
    name = Map.get(params, "name", "") |> String.trim()
    kind = Map.get(params, "kind", "openai")
    base_url = Map.get(params, "base_url", "") |> String.trim()
    api_key = Map.get(params, "api_key", "") |> String.trim()

    cond do
      name == "" ->
        {:noreply, flash(socket, :error, "Provider name is required.")}

      api_key == "" ->
        {:noreply, flash(socket, :error, "API key is required.")}

      base_url == "" ->
        {:noreply, flash(socket, :error, "Base URL is required.")}

      true ->
        account = "provider-" <> slugify(name)
        ref = Keychain.ref_for(account)

        with :ok <- Keychain.put(account, api_key),
             {:ok, provider} <-
               Control.create_provider(%{
                 name: name,
                 kind: kind,
                 base_url: base_url,
                 api_key_ref: ref
               }),
             {:ok, models} <- ProviderCatalog.fetch_models(provider),
             {:ok, _} <-
               Control.update_provider(provider, %{
                 models: %{"list" => models},
                 models_refreshed_at: DateTime.utc_now(),
                 last_error: nil
               }) do
          {:noreply,
           socket
           |> assign(:providers, Control.list_providers())
           |> assign(:form, to_new_form())
           |> flash(:info, "Saved \"#{name}\" and discovered #{length(models)} models.")}
        else
          {:error, %Ecto.Changeset{} = cs} ->
            {:noreply, flash(socket, :error, "Save failed: #{format_changeset_errors(cs)}.")}

          {:error, reason} ->
            # Save succeeded but model fetch failed — record the error.
            handle_partial_failure(socket, name, reason)
        end
    end
  end

  def handle_event("refresh", %{"id" => id}, socket) do
    case Control.get_provider(id) do
      nil ->
        {:noreply, flash(socket, :error, "Provider not found.")}

      provider ->
        case ProviderCatalog.fetch_models(provider) do
          {:ok, models} ->
            {:ok, _} =
              Control.update_provider(provider, %{
                models: %{"list" => models},
                models_refreshed_at: DateTime.utc_now(),
                last_error: nil
              })

            {:noreply,
             socket
             |> assign(:providers, Control.list_providers())
             |> flash(:info, "Refreshed \"#{provider.name}\" — #{length(models)} models.")}

          {:error, reason} ->
            {:ok, _} = Control.update_provider(provider, %{last_error: inspect(reason)})

            {:noreply,
             socket
             |> assign(:providers, Control.list_providers())
             |> flash(:error, "Refresh failed: #{inspect(reason)}.")}
        end
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Control.get_provider(id) do
      nil ->
        {:noreply, flash(socket, :error, "Provider not found.")}

      provider ->
        # Keychain account name derives from provider name; tear it down too.
        account = "provider-" <> slugify(provider.name)
        :ok = Keychain.delete(account)
        {:ok, _} = Control.delete_provider(provider)

        {:noreply,
         socket
         |> assign(:providers, Control.list_providers())
         |> flash(:info, "Deleted \"#{provider.name}\".")}
    end
  end

  # ─── render ───────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div style="max-width: 980px; margin: 24px auto; font-family: -apple-system, BlinkMacSystemFont, sans-serif; color: #1f2937;">
      <header style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 24px;">
        <h1 style="font-size: 28px; margin: 0;">Providers</h1>
        <nav style="display: flex; gap: 16px;">
          <.link navigate="/" style="color: #2563eb; text-decoration: none;">Dashboard</.link>
          <.link navigate="/projects" style="color: #2563eb; text-decoration: none;">Projects</.link>
          <.link navigate="/providers" style="color: #1f2937; font-weight: 600;">Providers</.link>
        </nav>
      </header>

      <%= if @flash_message do %>
        <div style={"padding: 12px 16px; border-radius: 8px; margin-bottom: 16px; background: #{flash_bg(@flash_kind)}; color: #{flash_fg(@flash_kind)}; border: 1px solid #{flash_border(@flash_kind)};"}>
          {@flash_message}
        </div>
      <% end %>

      <section style="background: #ffffff; border: 1px solid #e5e7eb; border-radius: 12px; padding: 20px; margin-bottom: 24px;">
        <h2 style="font-size: 18px; margin: 0 0 12px;">Add provider</h2>
        <p style="color: #6b7280; margin: 0 0 16px; font-size: 14px;">
          API keys are stored in the macOS Keychain under service "Symphony" — they're never persisted to the SQLite database in plaintext.
        </p>

        <form phx-submit="save" phx-change="change_kind" style="display: grid; gap: 12px; grid-template-columns: 1fr 1fr;">
          <label style="display: flex; flex-direction: column; gap: 4px;">
            <span style="font-size: 12px; color: #6b7280;">Display name</span>
            <input type="text" name="provider[name]" value={@form["name"]} placeholder="e.g. Anthropic – Personal"
              style="padding: 8px 10px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 14px;" />
          </label>

          <label style="display: flex; flex-direction: column; gap: 4px;">
            <span style="font-size: 12px; color: #6b7280;">Kind</span>
            <select name="provider[kind]" style="padding: 8px 10px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 14px;">
              <%= for p <- ProviderCatalog.presets() do %>
                <option value={p.kind} selected={p.kind == @form["kind"]}>{p.label}</option>
              <% end %>
            </select>
          </label>

          <label style="display: flex; flex-direction: column; gap: 4px; grid-column: 1 / span 2;">
            <span style="font-size: 12px; color: #6b7280;">Base URL</span>
            <input type="text" name="provider[base_url]" value={@form["base_url"]}
              style="padding: 8px 10px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 14px; font-family: monospace;" />
          </label>

          <label style="display: flex; flex-direction: column; gap: 4px; grid-column: 1 / span 2;">
            <span style="font-size: 12px; color: #6b7280;">API key</span>
            <input type="password" name="provider[api_key]" value=""
              autocomplete="off" placeholder="sk-..."
              style="padding: 8px 10px; border: 1px solid #d1d5db; border-radius: 6px; font-size: 14px; font-family: monospace;" />
            <span style="font-size: 11px; color: #9ca3af;">Stored in macOS Keychain. Never sent anywhere except the provider's API.</span>
          </label>

          <button type="submit" style="grid-column: 1 / span 2; justify-self: start; padding: 9px 16px; background: #2563eb; color: white; border: 0; border-radius: 6px; font-size: 14px; font-weight: 600; cursor: pointer;">
            Save & discover models
          </button>
        </form>
      </section>

      <section style="background: #ffffff; border: 1px solid #e5e7eb; border-radius: 12px; padding: 20px;">
        <h2 style="font-size: 18px; margin: 0 0 12px;">Configured providers</h2>

        <%= if @providers == [] do %>
          <p style="color: #9ca3af; font-size: 14px; margin: 0;">No providers yet. Add one above.</p>
        <% else %>
          <ul style="list-style: none; padding: 0; margin: 0; display: grid; gap: 12px;">
            <%= for p <- @providers do %>
              <li style="display: grid; grid-template-columns: 1fr auto; gap: 4px 16px; padding: 12px 16px; border: 1px solid #e5e7eb; border-radius: 8px;">
                <div style="display: flex; gap: 8px; align-items: baseline;">
                  <strong style="font-size: 15px;">{p.name}</strong>
                  <span style="font-size: 11px; padding: 2px 6px; background: #eef2ff; color: #4338ca; border-radius: 4px;">{p.kind}</span>
                </div>
                <div style="display: flex; gap: 8px;">
                  <button phx-click="refresh" phx-value-id={p.id}
                    style="padding: 4px 10px; background: #f3f4f6; border: 1px solid #d1d5db; border-radius: 4px; font-size: 12px; cursor: pointer;">
                    Refresh models
                  </button>
                  <button phx-click="delete" phx-value-id={p.id}
                    data-confirm={"Delete \"#{p.name}\"? Keychain entry will be removed too."}
                    style="padding: 4px 10px; background: #fef2f2; color: #b91c1c; border: 1px solid #fecaca; border-radius: 4px; font-size: 12px; cursor: pointer;">
                    Delete
                  </button>
                </div>
                <div style="grid-column: 1 / span 2; font-size: 12px; color: #6b7280; font-family: monospace;">
                  {p.base_url}
                </div>
                <%= if model_count(p) > 0 do %>
                  <div style="grid-column: 1 / span 2; font-size: 12px; color: #4b5563;">
                    {model_count(p)} models · refreshed {format_when(p.models_refreshed_at)}
                  </div>
                <% end %>
                <%= if p.last_error do %>
                  <div style="grid-column: 1 / span 2; font-size: 12px; color: #b91c1c;">
                    Last error: {p.last_error}
                  </div>
                <% end %>
              </li>
            <% end %>
          </ul>
        <% end %>
      </section>
    </div>
    """
  end

  # ─── helpers ──────────────────────────────────────────────────────────

  defp handle_partial_failure(socket, name, reason) do
    # If create_provider succeeded but model fetch failed, we still want to
    # show the provider in the list with the error attached.
    case Control.get_provider_by_name(name) do
      nil ->
        {:noreply, flash(socket, :error, "Failed: #{inspect(reason)}.")}

      provider ->
        {:ok, _} = Control.update_provider(provider, %{last_error: inspect(reason)})

        {:noreply,
         socket
         |> assign(:providers, Control.list_providers())
         |> assign(:form, to_new_form())
         |> flash(:error, "Saved \"#{name}\" but model discovery failed: #{inspect(reason)}.")}
    end
  end

  defp to_new_form do
    %{
      "name" => "",
      "kind" => "anthropic",
      "base_url" => "https://api.anthropic.com/v1",
      "api_key" => ""
    }
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp model_count(%Provider{models: %{"list" => list}}) when is_list(list), do: length(list)
  defp model_count(_), do: 0

  defp format_when(nil), do: "never"

  defp format_when(%DateTime{} = dt) do
    seconds_ago = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      seconds_ago < 60 -> "#{seconds_ago}s ago"
      seconds_ago < 3600 -> "#{div(seconds_ago, 60)}m ago"
      seconds_ago < 86400 -> "#{div(seconds_ago, 3600)}h ago"
      true -> "#{div(seconds_ago, 86400)}d ago"
    end
  end

  defp format_changeset_errors(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.map(fn {field, {msg, _opts}} -> "#{field} #{msg}" end)
    |> Enum.join(", ")
  end

  defp flash(socket, kind, msg) do
    socket |> assign(:flash_kind, kind) |> assign(:flash_message, msg)
  end

  defp flash_bg(:info), do: "#ecfdf5"
  defp flash_bg(:error), do: "#fef2f2"
  defp flash_bg(_), do: "#eff6ff"
  defp flash_fg(:info), do: "#065f46"
  defp flash_fg(:error), do: "#991b1b"
  defp flash_fg(_), do: "#1e3a8a"
  defp flash_border(:info), do: "#a7f3d0"
  defp flash_border(:error), do: "#fecaca"
  defp flash_border(_), do: "#bfdbfe"
end
