# AsyncTest

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
  `Agent` and retrieve it when needed

## Usage

Add `async_test` to deps:

```elixir
def deps do
  [
    {:async_test, github: "software-mansion-labs/elixir_async_test"}
  ]
end
```

In tests, `import AsyncTest` and replace `test` with `async_test`:

```diff
 defmodule MyTest do
   use ExUnit.Case

+  import AsyncTest

-  test "my test" do
+  async_test "my test" do
    assert true
   end
```

Now, all the `async_test`s will run asynchronously regardless of the module.

## Authors

AsyncTest is created by Software Mansion.

Since 2012 [Software Mansion](https://swmansion.com/) is a software agency with experience in building web and mobile apps as well as complex multimedia solutions. We are Core React Native Contributors and experts in live streaming and broadcasting technologies. We can help you build your next dream product – [Hire us](https://swmansion.com/contact/projects).

Copyright 2025, [Software Mansion](https://swmansion.com/)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/)

Licensed under the [Apache License, Version 2.0](LICENSE)