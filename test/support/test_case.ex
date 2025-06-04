defmodule TestCase do
  defmacro test_case(name, options \\ [], do: block) do
    module_name = Module.concat(__CALLER__.module, name)
    options = Keyword.merge([exclude: [], include: [], only_test_ids: nil], options)

    quote do
      test unquote(name) do
        ex_unit_config = ExUnit.configuration()
        on_exit(fn -> ExUnit.configure(ex_unit_config) end)

        defmodule unquote(module_name) do
          use ExUnit.Case

          import AsyncTest

          unquote(block)
        end

        ExUnit.configure(unquote(options))
        result = ExUnit.run([unquote(module_name)])
        assert %{failures: 0} = result
        result
      end
    end
  end
end
