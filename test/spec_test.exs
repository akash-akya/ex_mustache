defmodule ExMustache.SpecTest do
  use ExUnit.Case

  @spec_path Path.join(__DIR__, "../spec/specs")
  @ignored ["lambdas"]

  test "spec" do
    Temp.track!()

    Path.wildcard("#{@spec_path}/*.yml")
    |> Enum.reject(fn f -> Enum.any?(@ignored, &String.contains?(f, &1)) end)
    |> Enum.each(fn path ->
      IO.puts("\n=> #{path}")

      YamlElixir.read_from_file!(path)
      |> run_spec()
    end)
  end

  defp run_spec(%{"tests" => tests}) do
    Enum.each(tests, fn test ->
      try do
        temp_dir = Temp.mkdir!()
        create_partial_files(test["partials"], temp_dir)
        assert_test(test, temp_dir)
      after
        Temp.cleanup()
      end
    end)
  end

  defp create_partial_files(nil, _), do: :ok

  defp create_partial_files(partials, dir) do
    Enum.each(partials, fn {filename, content} ->
      File.write(Path.join(dir, filename <> ".mustache"), content, [:write])
    end)
  end

  defp assert_test(test, dir) do
    IO.puts(" " <> test["desc"])

    result =
      ExMustache.parse(test["template"], dir: dir)
      |> ExMustache.render(test["data"])
      |> IO.iodata_to_binary()

    assert test["expected"] == result
  end
end
