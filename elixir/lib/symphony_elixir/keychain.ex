defmodule SymphonyElixir.Keychain do
  @moduledoc """
  Thin wrapper over the macOS `security` CLI for storing and retrieving
  per-provider API keys. Keys are stored in the user's login keychain under
  the service name "Symphony", keyed by account name `provider-<provider name>`.

  Reference strings used in the DB look like:

      keychain:provider-anthropic-georgetranoz

  Calls fail loudly when `security` isn't on the PATH (e.g. on non-macOS).
  This is acceptable since Symphony is intended for local macOS use.
  """

  @service "Symphony"

  @doc """
  Store an API key for a provider. Idempotent — calling again with the same
  account updates the value (-U flag).
  """
  @spec put(String.t(), String.t()) :: :ok | {:error, term()}
  def put(account, value) when is_binary(account) and is_binary(value) do
    case System.cmd(
           "security",
           [
             "add-generic-password",
             "-a",
             account,
             "-s",
             @service,
             "-w",
             value,
             "-U"
           ],
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      {output, code} -> {:error, {:keychain_put_failed, code, output}}
    end
  end

  @doc """
  Fetch the API key for a provider. Returns `{:error, :not_found}` if no
  entry exists.
  """
  @spec get(String.t()) :: {:ok, String.t()} | {:error, term()}
  def get(account) when is_binary(account) do
    case System.cmd(
           "security",
           ["find-generic-password", "-a", account, "-s", @service, "-w"],
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, String.trim_trailing(output, "\n")}
      {_output, 44} -> {:error, :not_found}
      {output, code} -> {:error, {:keychain_get_failed, code, output}}
    end
  end

  @doc """
  Resolve a reference of the form `keychain:<account>` to the actual API
  key value. Non-keychain refs are returned untouched (useful for tests
  and environments without macOS).
  """
  @spec resolve(String.t()) :: {:ok, String.t()} | {:error, term()}
  def resolve("keychain:" <> account), do: get(account)
  def resolve(literal) when is_binary(literal), do: {:ok, literal}

  @doc """
  Delete a stored API key. Safe to call on a missing entry.
  """
  @spec delete(String.t()) :: :ok
  def delete(account) when is_binary(account) do
    System.cmd(
      "security",
      ["delete-generic-password", "-a", account, "-s", @service],
      stderr_to_stdout: true
    )

    :ok
  end

  @doc "Build the canonical reference string used in the providers.api_key_ref column."
  @spec ref_for(String.t()) :: String.t()
  def ref_for(account) when is_binary(account), do: "keychain:" <> account
end
