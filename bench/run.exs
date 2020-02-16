defmodule Bench do
  @fixture Path.join(__DIR__, "../fixture/")
  def run(file_name) do
    template = File.read!(Path.join(@fixture, "#{file_name}.hbs"))
    payload = File.read!(Path.join(@fixture, "#{file_name}.json")) |> Poison.decode!()
    run(template, payload)
  end

  def run(template, payload) do
    validate!(template, payload)
    benchmark_render(template, payload)
    benchmark_parse(template)
  end

  defp benchmark_parse(template) do
    Benchee.run(
      %{
        "parse: ex_mustache" => fn -> ex_mustache_parse(template) end,
        "parse: bbmustache" => fn -> bbmustache_parse(template) end
      },
      time: 10,
      memory_time: 2,
      formatters: [{Benchee.Formatters.Console, extended_statistics: true}]
    )
  end

  defp benchmark_render(template, payload) do
    bbmustache_template = bbmustache_parse(template)
    ex_mustache_template = ex_mustache_parse(template)

    Benchee.run(
      %{
        "render: ex_mustache" => fn -> ex_mustache_render(ex_mustache_template, payload) end,
        "render: bbmustache" => fn -> bbmustache_render(bbmustache_template, payload) end
      },
      time: 10,
      memory_time: 2,
      formatters: [{Benchee.Formatters.Console, extended_statistics: true}]
    )
  end

  defp bbmustache_parse(data), do: :bbmustache.parse_binary(data)

  defp bbmustache_render(template, payload) do
    :bbmustache.compile(template, payload, key_type: :binary)
  end

  defp ex_mustache_parse(data), do: ExMustache.parse(data)

  defp ex_mustache_render(template, payload) do
    ExMustache.render(template, payload) |> IO.iodata_to_binary()
  end

  defp validate!(template, payload) do
    expected = bbmustache_render(bbmustache_parse(template), payload)
    result = ex_mustache_render(ex_mustache_parse(template), payload)

    unless expected == result do
      raise "template mismatch. \nexpected: #{expected}\ngot: #{result}"
    end
  end
end

template = """
  Hello {{name}}
  You have just won {{value}} dollars!
  {{#in_ca}}
  Well, {{taxed_value}} dollars, after taxes.
  {{/in_ca}}
"""

payload = %{
  "name" => "Chris",
  "value" => 10000,
  "taxed_value" => 10000 - 10000 * 0.4,
  "in_ca" => true
}

# 60 bytes template
Bench.run(template, payload)

# 20KB template with positive block
Bench.run("template_1")

# 20KB template with negative block (best case scenario for ExMustache)
Bench.run("template_2")
