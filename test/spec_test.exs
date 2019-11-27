defmodule ExMustache.SpecTest do
  use ExUnit.Case

  @spec_path Path.join(__DIR__, "../spec/specs")

  test "run" do
    Path.wildcard("#{@spec_path}/*.yml")
    |> Enum.reject(fn f ->
      Enum.any?(["lambda"], fn ignored ->
        String.contains?(f, ignored)
      end)
    end)
    |> Enum.each(fn path ->
      IO.puts("\n=> #{path}")

      YamlElixir.read_from_file!(path)
      |> run_spec()
    end)
  end

  defp run_spec(%{"tests" => tests}) do
    Enum.each(tests, &assert_test/1)
  end

  defp assert_test(test) do
    IO.puts(" " <> test["desc"])

    result =
      ExMustache.tokenize(test["template"])
      |> ExMustache.parse()
      |> ExMustache.render(test["data"], test["partials"], [])
      |> IO.iodata_to_binary()

    assert test["expected"] == result
  end
end
