defmodule ExMustache.SpecTest do
  use ExUnit.Case

  @spec_path Path.join(__DIR__, "../spec/specs")

  test "run" do
    Path.wildcard("#{@spec_path}/*.yml")
    |> Enum.reject(fn f ->
      Enum.any?(["lambda", "delimiter", "partials"], fn ignored ->
        String.contains?(f, ignored)
      end)
    end)
    |> Enum.each(fn path ->
      IO.puts("testing #{path}")

      YamlElixir.read_from_file!(path)
      |> run_spec()
    end)
  end

  defp run_spec(%{"tests" => tests}) do
    Enum.each(tests, &assert_test/1)
  end

  defp assert_test(test) do
    IO.puts(test["desc"])

    result =
      ExMustache.tokenize(test["template"])
      |> ExMustache.parse()
      |> ExMustache.create_template_func()
      |> ExMustache.render(test["data"])
      |> IO.iodata_to_binary()

    assert test["expected"] == result
  end
end
