defmodule ExMustacheTest do
  use ExUnit.Case

  test "next_interpolation" do
    assert ["Hello ", {:variable, ["name"]}, "!"] == ExMustache.tokenize("Hello {{ name }}!")

    assert_raise(RuntimeError, ~s(Invalid Tag: ""), fn ->
      ExMustache.tokenize("Name {{   }}")
    end)

    template = ~s"""
    Test:
    {{#product}}

     {{name}}

    {{/product}}
    """

    assert [
             "Test:",
             "\n",
             {:block, ["product"]},
             "\n",
             " ",
             {:variable, ["name"]},
             "\n",
             "\n",
             {:block_close, ["product"]}
           ] == ExMustache.tokenize(template)
  end

  test "parser" do
    template = ExMustache.tokenize("Hello {{ name }}!")
    assert ["Hello ", {:variable, ["name"]}, "!"] == ExMustache.parse(template)

    template = ExMustache.tokenize("Test: {{#product}} {{name}} {{/product}}")

    assert [
             "Test: ",
             {:block, ["product"], [" ", {:variable, ["name"]}, " "]}
           ] == ExMustache.parse(template)
  end

  describe "create_template_func" do
    test "create_template_func" do
      template =
        ExMustache.tokenize("Hello {{ name }}!")
        |> ExMustache.parse()

      template = ExMustache.create_template_func(template)

      ExMustache.render(template, %{"name" => "Akash"})
      |> to_string()
      |> IO.inspect()
    end

    test "nested" do
      template =
        ExMustache.tokenize("Test: {{#product}}{{name}}{{/product}}")
        |> ExMustache.parse()
        |> ExMustache.create_template_func()

      ExMustache.render(template, %{
        "name" => "Akash",
        "product" => %{}
      })
      |> IO.iodata_to_binary()
      |> IO.inspect()
    end

    test "deep nested" do
      template = ~s"""
      Hello {{ name }}!
      {{#dummy}}
      x   {{ #movies }}  x
        Movies:
          Watched:
          {{ #watched }}
            - {{ name }}
          {{ /watched }}
      {{ /movies }}
      {{/dummy}}
      """

      data = %{
        "name" => "Akash",
        "dummy" => %{"watched" => [%{"name" => "Pulp Fiction"}, %{"name" => "The God Father"}]},
        "movies" => "ss"
      }

      :bbmustache.render(template, data, key_type: :binary)
      |> IO.puts()

      template =
        ExMustache.tokenize(template)
        |> ExMustache.parse()
        |> ExMustache.create_template_func()

      ExMustache.render(template, data)
      |> IO.iodata_to_binary()
      |> IO.puts()
    end

    test "deep nested test" do
      template = ~s"""
      {{#dummy}}
        {{ #test }}
          {{ #movies }}
            - {{ dummy..name }}
          {{ /movies }}
        {{ /test }}
      {{/dummy}}
      """

      data = %{
        "dummy" => %{
          "name" => "wrong",
          "test" => %{
            "name" => "right",
            "movies" => "error"
          }
        }
      }

      :bbmustache.render(template, data, key_type: :binary)
      |> IO.puts()

      template =
        ExMustache.tokenize(template)
        |> ExMustache.parse()
        |> ExMustache.create_template_func()

      ExMustache.render(template, data)
      |> IO.iodata_to_binary()
      |> IO.puts()
    end

    test "mustache" do
      template = ~s"""
      Test:
      {{#product}}

       {{name}}

      {{/product}}
      """

      data = %{
        "product" => %{
          "name" => "abcd"
        }
      }

      mu = :bbmustache.render(template, data, key_type: :binary)

      mymu =
        ExMustache.tokenize(template)
        |> ExMustache.parse()
        |> ExMustache.create_template_func()
        |> ExMustache.render(data)
        |> IO.iodata_to_binary()

      assert mu == mymu
    end
  end
end
