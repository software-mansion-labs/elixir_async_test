defmodule AsyncTest do
  @moduledoc """
  Makes tests within a single module (ExUnit Case) run asynchronously.

  Just `import #{inspect(__MODULE__)}` and replace
  `test` with `async_test`. It should be a drop-in
  replacement.

  #{inspect(__MODULE__)} works in the following way:
  - create a public function instead of a test
  - create a new module with a single test that calls that function
  - mimic `@tags`, `setup`, `setup_all`, and `describe` structure
  in the new module
  - ensure `setup_all` is called only once - store its result in an
  `Agent` and retrieve it when needed
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
    unquoted = {:unquote, [], [quoted]}
    # That's what `Macro.escape_once` would do.
    # We escape one level not to escape `code` which is already
    # quoted.
    escaped_once = {:{}, [], Tuple.to_list(unquoted)}
    escaped_once
  end

  @doc @moduledoc
  if Application.compile_env(:async_test, :fallback_to_test, false) do
    defmacro async_test(test_name, context \\ quote(do: _context), do: block) do
      quote do
        test unquote(test_name), unquote(context) do
          unquote(block)
        end
      end
    end
  else
    defmacro async_test(test_name, context \\ quote(do: _context), do: block) do
      do_async_test(test_name, context, block)
    end
  end

  defp do_async_test(test_name, context, block) do
    quote do
      params = AsyncTest.CreateTestUtils.params(unquote(test_name), __MODULE__)

      def unquote(unquoted(params.fun_name))(unquote(context)) do
        unquote(block)
      end

      escaped_params = Macro.escape(params)

      def unquote(unquoted(params.after_compile_fun_name))(_bytecode, _env) do
        params = unquote(unquoted(escaped_params))
        AsyncTest.CreateTestUtils.create_module(__MODULE__, params)
      end

      unless AsyncTest.CreateTestUtils in @before_compile do
        @before_compile AsyncTest.CreateTestUtils
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
    describe =
      case Module.get_attribute(module, :ex_unit_describe) do
        {_line, name, _idx} -> name
        nil -> nil
      end

    test_name = "#{if describe, do: "#{describe} ", else: ""}#{test_name}"
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
      test_module_name: test_module_name(module, test_name),
      fun_name: fun_name,
      after_compile_fun_name: :"async_test_ac_#{test_name}",
      tags_attrs: tags_attrs,
      describe: describe
    }
  end

  defmacro __before_compile__(env) do
    describes =
      Module.get_attribute(env.module, :ex_unit_used_describes)
      |> Map.values()
      |> Enum.reject(&(&1 == nil))
      |> Enum.map(&proxy_test_fun(&1, :describe))

    setups =
      setups_to_proxy(env.module, :ex_unit_setup)
      |> Enum.map(&proxy_test_fun(&1, :setup))

    setup_alls =
      setups_to_proxy(env.module, :ex_unit_setup_all)
      |> Enum.map(fn fun ->
        transform =
          &quote do
            AsyncTest.CreateTestUtils.agent_cache(__MODULE__, unquote(fun), fn -> unquote(&1) end)
          end

        proxy_test_fun(fun, :setup_all, transform)
      end)

    quote do
      unquote_splicing(describes)
      unquote_splicing(setups)
      unquote_splicing(setup_alls)
    end
  end

  def create_module(caller_module, params) do
    setups = setups_attr(caller_module, :ex_unit_setup, :setup)
    setup_alls = setups_attr(caller_module, :ex_unit_setup_all, :setup_all)
    describe_setups = describe_setups(caller_module, params.describe)

    case_options =
      Macro.escape(Module.get_attribute(caller_module, :ex_unit_module, []) ++ [async: true])

    content =
      quote do
        use ExUnit.Case, unquote(case_options)

        Enum.each(unquote(params.tags_attrs), fn {name, value} ->
          Module.put_attribute(__MODULE__, name, value)
        end)

        @ex_unit_setup unquote(describe_setups ++ setups)
        @ex_unit_setup_all unquote(setup_alls)

        test unquote(params.test_name), context do
          unquote(caller_module).unquote(params.fun_name)(context)
        end
      end

    Module.create(params.test_module_name, content, __ENV__)
  end

  def agent_cache(module, name, fun) do
    agent_name = Module.concat([__MODULE__, :setup_all, module, name])
    Agent.start_link(fun, name: agent_name)
    Agent.get(agent_name, & &1)
  end

  defp setups_to_proxy(module, attr_name) do
    Module.get_attribute(module, attr_name)
    |> Enum.flat_map(fn
      {_module, _fun} -> []
      fun -> [fun]
    end)
  end

  defp setups_attr(module, attr_name, prefix) do
    Module.get_attribute(module, attr_name)
    |> Enum.map(fn
      {module, fun} -> {module, fun}
      fun -> {module, fun_prefix(fun, prefix)}
    end)
  end

  defp describe_setups(module, describe) do
    describes = Module.get_attribute(module, :ex_unit_used_describes)

    if fun = Map.get(describes, describe) do
      [{module, fun_prefix(fun, :describe)}]
    else
      []
    end
  end

  defp proxy_test_fun(fun, proxy_prefix, transform \\ &Function.identity/1) do
    call = transform.(quote do: unquote(fun)(ctx))

    quote do
      def unquote(fun_prefix(fun, proxy_prefix))(ctx) do
        unquote(call)
      end
    end
  end

  defp fun_prefix(name, prefix) do
    :"__async_test_#{prefix}#{name}"
  end

  defp test_fun_defined?(module, name) do
    Module.defines?(module, {name, 1})
  end

  defp test_module_name(module, test_name) do
    escaped_test_name = String.replace(test_name, ~r/[^A-Za-z0-9]/, "_")

    short_hash =
      "#{module}/#{test_name}"
      |> :erlang.md5()
      |> Base.encode16(case: :lower)
      |> binary_slice(0..7)

    Module.concat(module, "AT_#{escaped_test_name}_#{short_hash}")
  end
end
