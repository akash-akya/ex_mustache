# ExMustache [![Hex.pm](https://img.shields.io/hexpm/v/ex_mustache.svg)](https://hex.pm/packages/ex_mustache)

ExMustache is fast mustache templating library for Elixir.

ExMustache supports everything except lambda from mustache spec. It is faster and uses lesser memory when compared to alternatives. ExMustache is a pure elixir implementation.

## Installation

```elixir
def deps do
  [
    {:ex_mustache, "~> x.x.x"}
  ]
end
```

## Usage
```elixir
# Parse once
mustache_template = "Hello {{name}}\n You have just won {{value}} dollars"
template = ExMustache.parse(mustache_template)


# Render multiple times
iodata = ExMustache.render(template, %{"name" => "Chris", "value" => 10000})
IO.puts(iodata)

iodata = ExMustache.render(template, %{"name" => "Bob", "value" => 20000})
IO.puts(iodata)
```

Note that `render/2` returns iodata, which an efficient data structure for IO. Most of the IO operation accepts iodata so we can pass the rendered content without converting it to a binary. If you need rendered content as string, `IO.iodata_to_binary/1` can be used. More about [iodata](https://hexdocs.pm/elixir/IO.html#module-io-data)

## Performance
With my [*unscientific* benchmarking](https://github.com/akash-akya/ex_mustache/tree/master/bench), when compared to [bbmustache](https://github.com/soranoba/bbmustache) (which is already a fast implementation), ExMustache is from 5 to 2 times faster and use 20 to 2 times lesser memory for *redering*. You can check the results [here](https://github.com/akash-akya/ex_mustache/tree/master/bench/BENCHMARK.md). These numbers vary a lot depending on the template, so take these number with grain of salt and please benchmark for your usecase if you are concerned with the performance. Check benchmark script sample case. Worst case scenario it should be at least as good as bbmustache.

Since ExMustache is optimized for rendering, parsing might use 4 to 2 times more memory compared to bbmustache.

Partial templates should be avoided to get better performance.
