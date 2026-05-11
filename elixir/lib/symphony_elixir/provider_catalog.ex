defmodule SymphonyElixir.ProviderCatalog do
  @moduledoc """
  Knowledge about the LLM providers Symphony can talk to. Each kind has a
  default base URL, an authorisation header style, and a strategy for
  listing available models.

  The catalog is intentionally small — adding a new provider is a matter of
  adding a row to `@presets` and (if needed) a `fetch_models/2` clause.
  """

  require Logger

  @presets [
    %{
      kind: "anthropic",
      label: "Anthropic",
      base_url: "https://api.anthropic.com/v1",
      auth: :x_api_key
    },
    %{
      kind: "openai",
      label: "OpenAI",
      base_url: "https://api.openai.com/v1",
      auth: :bearer
    },
    %{
      kind: "deepseek",
      label: "DeepSeek",
      base_url: "https://api.deepseek.com/v1",
      auth: :bearer
    },
    %{
      kind: "google",
      label: "Google (Gemini)",
      base_url: "https://generativelanguage.googleapis.com/v1beta",
      auth: :google_key
    },
    %{
      kind: "openrouter",
      label: "OpenRouter",
      base_url: "https://openrouter.ai/api/v1",
      auth: :bearer
    },
    %{
      kind: "custom",
      label: "Custom (OpenAI-compatible)",
      base_url: "",
      auth: :bearer
    }
  ]

  @doc "All preset provider kinds in display order."
  @spec presets() :: [map()]
  def presets, do: @presets

  @doc "Find a preset by kind. Returns nil if unknown."
  @spec preset(String.t()) :: map() | nil
  def preset(kind), do: Enum.find(@presets, &(&1.kind == kind))

  @doc """
  Discover available model identifiers for a provider. The provider must
  have a resolvable api_key_ref. Returns `{:ok, [model_name]}` on success
  or `{:error, reason}`.
  """
  @spec fetch_models(SymphonyElixir.Control.Provider.t()) :: {:ok, [String.t()]} | {:error, term()}
  def fetch_models(%{kind: kind, base_url: base_url, api_key_ref: ref}) do
    with {:ok, api_key} <- SymphonyElixir.Keychain.resolve(ref),
         {:ok, models} <- do_fetch_models(kind, String.trim_trailing(base_url, "/"), api_key) do
      {:ok, models}
    end
  end

  # ─── per-kind fetch implementations ───────────────────────────────────

  defp do_fetch_models("anthropic", base_url, api_key) do
    # Anthropic's /v1/models needs x-api-key + anthropic-version headers.
    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"}
    ]

    case Req.get(base_url <> "/models", headers: headers) do
      {:ok, %{status: 200, body: %{"data" => data}}} when is_list(data) ->
        {:ok, Enum.map(data, & &1["id"]) |> Enum.reject(&is_nil/1) |> Enum.sort()}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_status, status, body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp do_fetch_models("google", base_url, api_key) do
    # Google's listModels takes the key as a query param.
    case Req.get(base_url <> "/models", params: [key: api_key]) do
      {:ok, %{status: 200, body: %{"models" => models}}} when is_list(models) ->
        names =
          models
          |> Enum.map(fn m ->
            case m["name"] do
              "models/" <> short -> short
              other -> other
            end
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.sort()

        {:ok, names}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_status, status, body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp do_fetch_models(_kind, base_url, api_key) do
    # OpenAI-compatible shape: GET /models with Bearer auth.
    case Req.get(base_url <> "/models", headers: [{"Authorization", "Bearer " <> api_key}]) do
      {:ok, %{status: 200, body: %{"data" => data}}} when is_list(data) ->
        {:ok, Enum.map(data, & &1["id"]) |> Enum.reject(&is_nil/1) |> Enum.sort()}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_status, status, body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end
end
