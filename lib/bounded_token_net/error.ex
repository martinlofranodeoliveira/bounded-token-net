defmodule BoundedTokenNet.Error do
  @moduledoc "A bounded diagnostic. Error results never contain a changed marking."
  @enforce_keys [:code, :at]
  defstruct [:code, :at, details: %{}]

  @type t :: %__MODULE__{code: atom(), at: String.t(), details: map()}

  @doc false
  def error(code, at, details \\ %{}) do
    {:error, %__MODULE__{code: code, at: at, details: details}}
  end
end
