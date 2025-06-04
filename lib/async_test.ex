defmodule AsyncTest do
  @moduledoc """
  Makes tests within a single module run asynchronously.

  Just `import #{inspect(__MODULE__)}` and replace
  `test` with `async_test`. It should be a drop-in
  replacement.

  #{inspect(__MODULE__)} works in the following way:
  - create a public function instead of a test
  - create a new module with a single test that calls that function
  - copy all `@tags` to the newly created module
  - handle `setup` and `setup_all` similarly to `test`s - the `setup`
  in the new module calls a public function from the original module
  - ensure `setup_all` is called only once - store its result in an
  `Agent` and retrieve when needed
  """

  # Like `unquote`, but only one level up in nested `quote`s tree.
  # For example:
  #
  # foo = 1
  # quote do
  #   bar = 1
  #   quote do
  #     unquote(foo) # use unquote to access foo
  #     unquote(unquoted(bar)) # use unquoted to access bar
  #   end
  # end
  defmacrop unquoted(code) do
    # Quote, because we need to return AST that generates AST.
    # `Macro.escape` drops variables' context and therefore
    # doesn't work.
    quoted = {:quote, [], [[do: code]]}
    # Unquote, because that's what this macro does
    unquoted = [:unquote, [], [quoted]]
    # That's what `Macro.escape_once` would do.
    # We escape one level not to escape `code` which is already
    # quoted.
    escaped_once = {:{}, [], unquoted}
    escaped_once
  end

  @doc @moduledoc
  defmacro async_test(test_name, context \\ quote(do: _context), do: block) do
    quote do
      params = AsyncTest.CreateTestUtils.params(unquote(test_name), __MODULE__)

      Enum.each(params.setups.proxies, fn %{proxy: proxy, fun: fun} ->
        def unquote(unquoted(proxy))(ctx) do
          unquote(unquoted(fun))(ctx)
        end
      end)

      Enum.each(params.setup_alls.proxies, fn %{proxy: proxy, fun: fun} ->
        def unquote(unquoted(proxy))(ctx) do
          agent_name = Module.concat(__MODULE__, unquote(unquoted(proxy)))
          Agent.start_link(fn -> unquote(unquoted(fun))(ctx) end, name: agent_name)
          Agent.get(agent_name, & &1)
        end
      end)

      def unquote(unquoted(params.fun_name))(unquote(context)) do
        unquote(block)
      end

      escaped_params = Macro.escape(params)

      def unquote(unquoted(params.after_compile_fun_name))(_bytecode, _env) do
        params = unquote(unquoted(escaped_params))
        AsyncTest.CreateTestUtils.create_module(__MODULE__, params)
      end

      @after_compile {__MODULE__, params.after_compile_fun_name}

      Module.delete_attribute(__MODULE__, :tag)
    end
  end
end

defmodule AsyncTest.CreateTestUtils do
  @moduledoc false
  # Module with utility functions, kept here not to be imported
  # with `import AsyncTest`. These utility functions exist to keep
  # the generated code (relatively) small.

  def params(test_name, module) do
    fun_name = :"async_test_#{test_name}"

    if test_fun_defined?(module, fun_name) do
      raise "Test already defined: #{test_name}"
    end

    tags_attrs =
      [:tag, :describetag, :moduletag]
      |> Enum.flat_map(fn attr ->
        Module.get_attribute(module, attr) |> Enum.map(&{attr, &1})
      end)

    %{
      test_name: test_name,
      test_module_name: Module.concat(module, "AsyncTest_#{test_name}"),
      fun_name: fun_name,
      after_compile_fun_name: :"async_test_ac_#{test_name}",
      setups: setups_proxies(module, :ex_unit_setup),
      setup_alls: setups_proxies(module, :ex_unit_setup_all),
      tags_attrs: tags_attrs
    }
  end

  def create_module(caller_module, params) do
    content =
      quote do
        use ExUnit.Case, async: true

        Enum.each(unquote(params.tags_attrs), fn {name, value} ->
          Module.put_attribute(__MODULE__, name, value)
        end)

        @ex_unit_setup unquote(params.setups.proxied_attr)
        @ex_unit_setup_all unquote(params.setup_alls.proxied_attr)

        test unquote(params.test_name), context do
          unquote(caller_module).unquote(params.fun_name)(context)
        end
      end

    Module.create(params.test_module_name, content, __ENV__)
  end

  defp setups_proxies(module, attr_name) do
    attr = Module.get_attribute(module, attr_name)

    proxied_attr =
      Enum.map(attr, fn
        {module, fun} -> {module, fun}
        fun -> {module, :"__async_test_#{attr_name}#{fun}"}
      end)

    proxies =
      Enum.flat_map(attr, fn
        {_module, _fun} -> []
        fun -> [%{fun: fun, proxy: :"__async_test_#{attr_name}#{fun}"}]
      end)
      |> Enum.reject(&test_fun_defined?(module, &1.proxy))

    %{proxied_attr: proxied_attr, proxies: proxies}
  end

  defp test_fun_defined?(module, name) do
    Module.defines?(module, {name, 1})
  end
end
