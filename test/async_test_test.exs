defmodule AsyncTestTest do
  use ExUnit.Case

  import TestCase

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
    async_test "test 1" do
      check_for_async()
    end

    async_test "test 2" do
      check_for_async()
    end

    defp check_for_async() do
      task_name = __MODULE__.CheckForAsync

      {:ok, pid} =
        Task.start_link(fn ->
          pid1 = receive do: ({:test, pid} -> pid)
          pid2 = receive do: ({:test, pid} -> pid)
          send(pid1, :ok)
          send(pid2, :ok)
        end)

      try do
        Process.register(pid, task_name)
      rescue
        _e -> :ok
      end

      send(task_name, {:test, self()})
      assert_receive :ok, 5000
    end
  end
end
