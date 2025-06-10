defmodule TestCase do
  @moduledoc """
  Utility for creating and running test cases within tests.
  """
  defmacro test_case(name, options \\ [], do: block) do
    module_name =
      Module.concat(__CALLER__.module, :"Case_#{String.replace(name, ~r/[^A-Za-z0-9]/, "_")}")

    ex_unit_options =
      Keyword.merge(
        [exclude: [], include: [], only_test_ids: nil],
        Keyword.get(options, :ex_unit, [])
      )

    case_options = Keyword.get(options, :case, [])

    assertions =
      Keyword.get(options, :result, [])
      |> Keyword.put_new(:failures, 0)
      |> Enum.map(fn {k, v} ->
        quote do
          assert unquote(Macro.escape(v)) == result[unquote(Macro.escape(k))]
        end
      end)

    quote do
      test unquote(name) do
        ex_unit_config = ExUnit.configuration()
        on_exit(fn -> ExUnit.configure(ex_unit_config) end)

        defmodule unquote(module_name) do
          use ExUnit.Case, unquote(case_options)

          import AsyncTest

          @moduletag :tmp_dir

          unquote(block)
        end

        ExUnit.configure(unquote(ex_unit_options))
        result = ExUnit.run([unquote(module_name)])

        unquote_splicing(assertions)
        result
      end
    end
  end
end
