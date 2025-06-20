defmodule AsyncTestTest do
  use ExUnit.Case

  import TestCase

  test_case "tests work asynchronously" do
    @num_tests 5

    Enum.each(1..@num_tests, fn i ->
      async_test "test #{i}" do
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

  test_case "Tags", ex_unit: [exclude: :b] do
    @tag :a
    async_test "a" do
      :ok
    end

    @tag :b
    async_test "b" do
      assert false
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

  test_case "setup all" do
    setup_all do
      {:ok, _pid} = Agent.start_link(fn -> :ok end, name: __MODULE__.A1)
      [foo: :bar]
    end

    setup_all do
      {:ok, _pid} = Agent.start_link(fn -> :ok end, name: __MODULE__.A2)
      [bar: :baz]
    end

    async_test "test 1", ctx do
      assert ctx.foo == :bar
      assert ctx.bar == :baz
    end

    async_test "test 2", ctx do
      assert ctx.foo == :bar
      assert ctx.bar == :baz
    end
  end

  test_case "describe" do
    setup do
      [foo: 0, bar: 0]
    end

    setup_all do
      [foo_all: 0]
    end

    describe "describe 1" do
      setup do
        [foo: 1]
      end

      async_test "test 1", ctx do
        assert ctx.foo == 1
        assert ctx.bar == 0
        assert ctx.baz == 0
        assert ctx.foo_all == 0
      end
    end

    describe "describe 2" do
      async_test "test", ctx do
        assert ctx.foo == 0
        assert ctx.bar == 0
        assert ctx.baz == 0
        assert ctx.foo_all == 0
      end
    end

    describe "describe 3" do
      setup do
        [foo: 2]
      end

      async_test "test 1", ctx do
        assert ctx.foo == 2
        assert ctx.bar == 0
        assert ctx.baz == 1
        assert ctx.foo_all == 0
      end

      setup do
        [baz: 1]
      end

      async_test "test 2", ctx do
        assert ctx.foo == 2
        assert ctx.bar == 0
        assert ctx.baz == 1
        assert ctx.foo_all == 0
      end
    end

    setup do
      [baz: 0]
    end
  end

  if Version.compare("1.18.0", System.version()) != :gt do
    test_case "parameterize", case: [parameterize: [%{p: 1}, %{p: 2}]] do
      setup_all do
        {:ok, pid} = Agent.start_link(fn -> nil end)
        [agent: pid]
      end

      async_test "test", ctx do
        pid = self()

        Agent.update(ctx.agent, fn
          nil ->
            {:param, pid, ctx.p}

          {:param, other_pid, param} ->
            Enum.each([pid, other_pid], &send(&1, Enum.sort([param, ctx.p])))
        end)

        assert_receive [1, 2]
      end
    end
  end

  test "duplicate name" do
    assert_raise RuntimeError, "Test already defined: foo", fn ->
      defmodule __MODULE__.RepeatedName do
        use ExUnit.Case
        import AsyncTest

        async_test("foo", do: :ok)
        async_test("foo", do: :ok)
      end
    end
  end

  test_case "weird name" do
    async_test "$%/\\^9" do
      :ok
    end
  end

  defmodule FailureFormatter do
    use GenServer

    @impl true
    def init(_opts) do
      {:ok, %{}}
    end

    @impl true
    def handle_cast({:test_finished, test}, state) do
      assert %ExUnit.Test{state: {:failed, failures}} = test

      assert [
               {:error, %ExUnit.AssertionError{message: message},
                [{_m, _f, _a, file: file, line: line}]}
             ] = failures

      assert message == "test location: #{file}:#{line}"
      {:noreply, state}
    end

    @impl true
    def handle_cast(_request, state) do
      {:noreply, state}
    end
  end

  test_case "failure location", result: [failures: 1], ex_unit: [formatters: [FailureFormatter]] do
    async_test "test" do
      assert false, "test location: #{Path.relative_to_cwd(__ENV__.file)}:#{__ENV__.line - 1}"
    end
  end

  test_case "mix test --only location",
    result: [excluded: 1],
    ex_unit: [
      exclude: :test,
      include: [location: {Path.relative_to_cwd(__ENV__.file), __ENV__.line + 2}]
    ] do
    async_test "test 1" do
      :ok
    end

    async_test "test 2" do
      :ok
    end
  end
end
