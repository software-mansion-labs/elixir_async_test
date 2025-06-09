# AsyncTest

 Makes tests within a single module (ExUnit Case) run asynchronously.

  Just `import AsyncTest` and replace `test`s with `async_test`s. It should be a drop-in replacement.

  AsyncTest works in the following way:
  - create a public function instead of a test
  - create a new module with a single test that calls that function
  - mimic `@tags`, `setup`, `setup_all`, and `describe` structure in the new module
  - ensure `setup_all` is called only once - store its result in an
  `Agent` and retrieve it when needed

## Usage

Add `async_test` to deps:

```elixir
def deps do
  [
    {:async_test, github: "software-mansion-labs/elixir_async_test", only: :test}
  ]
end
```

In tests, `import AsyncTest` and replace `test`s with `async_test`s:

```diff
 defmodule MyTest do
   use ExUnit.Case

+  import AsyncTest

-  test "my test" do
+  async_test "my test" do
    assert true
   end
 end
```

Now, all the `async_test`s will run asynchronously regardless of the module.

## Motivation

TL;DR Async tests in a single module may harm performance instead of improving it, thus ExUnit doesn't support them, but in particular cases they're beneficial.

ExUnit always runs tests in a single module synchronously (except of [parameterized tests](https://hexdocs.pm/ex_unit/ExUnit.Case.html#module-parameterized-tests)). [This PR](https://github.com/elixir-lang/elixir/pull/13283) was an attempt to change it, but, as described there, it didn't bring improvement to examined projects.

Sometimes, though, async tests in a single module help a lot. One example is [Boombox](https://github.com/membraneframework/boombox), where there's a lot of IO-bound, independent tests, and no reason to move them to different modules. Another one is [Popcorn](https://github.com/software-mansion/popcorn), where tests are CPU-bound, but also independent and very unevenly distributed across modules.

## Authors

AsyncTest is created by Software Mansion.

Since 2012 [Software Mansion](https://swmansion.com/) is a software agency with experience in building web and mobile apps as well as complex multimedia solutions. We are Core React Native Contributors and experts in live streaming and broadcasting technologies. We can help you build your next dream product – [Hire us](https://swmansion.com/contact/projects).

Copyright 2025, [Software Mansion](https://swmansion.com/)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/)

Licensed under the [Apache License, Version 2.0](LICENSE)