defmodule AsyncTestTest do
  use ExUnit.Case

  import TestCase

  test "repeated name" do
    assert_raise RuntimeError, "Test already defined: foo", fn ->
      defmodule __MODULE__.RepeatedName do
        use ExUnit.Case
        import AsyncTest

        async_test("foo", do: :ok)
        async_test("foo", do: :ok)
      end
    end
  end

  test_case "setup all" do
    setup_all do
      {:ok, _pid} = Agent.start_link(fn -> :ok end, name: __MODULE__)
      [foo: :bar]
    end

    async_test "test 1", ctx do
      assert ctx.foo == :bar
    end

    async_test "test 2", ctx do
      assert ctx.foo == :bar
    end
  end

  test_case "setup" do
    setup do
      [foo: :bar]
    end

    async_test "test", ctx do
      assert ctx.foo == :bar
    end
  end

  test_case "Tags", exclude: :b do
    @tag :a
    async_test "a" do
      :ok
    end

    @tag :b
    async_test "b" do
      assert false
    end
  end

  test_case "tests work asynchronously" do
    @num_tests 5

    Enum.each(1..@num_tests, fn i ->
      async_test "test #{i}}" do
        perform_test()
      end
    end)

    defp perform_test() do
      agent_name = __MODULE__.CheckForAsync

      Agent.start_link(fn -> [] end, name: agent_name)
      pid = self()

      Agent.update(agent_name, fn pids ->
        pids = [pid | pids]

        if length(pids) == @num_tests do
          Enum.each(pids, &send(&1, :ok))
        end

        pids
      end)

      assert_receive :ok
    end
  end
end
