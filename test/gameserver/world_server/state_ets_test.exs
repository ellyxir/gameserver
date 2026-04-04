defmodule Gameserver.WorldServer.StateETSTest do
  use ExUnit.Case, async: true

  alias Gameserver.WorldServer.StateETS

  setup do
    name = :"state_ets_#{System.unique_integer([:positive])}"
    state_ets = start_supervised!({StateETS, name: name})
    %{state_ets: state_ets}
  end

  describe "save_seed/2 and get_seed/1" do
    test "stores and retrieves a seed", %{state_ets: state_ets} do
      :ok = StateETS.save_seed(42, state_ets)
      assert StateETS.get_seed(state_ets) == 42
    end

    test "overwrites seed with a new value", %{state_ets: state_ets} do
      :ok = StateETS.save_seed(42, state_ets)
      :ok = StateETS.save_seed(99, state_ets)
      assert StateETS.get_seed(state_ets) == 99
    end
  end
end
