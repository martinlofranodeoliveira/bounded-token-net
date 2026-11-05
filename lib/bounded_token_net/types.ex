defmodule BoundedTokenNet.Marking do
  @moduledoc "An immutable token vector bound to ordered place IDs and capacities."
  @enforce_keys [:places, :capacities, :tokens]
  defstruct [:places, :capacities, :tokens]
end

defmodule BoundedTokenNet.Transition do
  @moduledoc "A validated dense transition bound to an ordered place schema."
  @enforce_keys [:id, :places, :capacities, :pre, :post]
  defstruct [:id, :places, :capacities, :pre, :post]
end
