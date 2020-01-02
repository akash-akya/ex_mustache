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
    Enum.each(tests, fn test ->
      delete_mustache_files()
      create_partial_files(test["partials"])
      assert_test(test)
    end)
  end

  defp create_partial_files(nil), do: :ok

  defp create_partial_files(partials) do
    Enum.each(partials, fn {filename, content} ->
      File.write(Path.absname(filename <> ".mustache"), content, [:write])
    end)
  end

  defp delete_mustache_files() do
    File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".mustache"))
    |> Enum.each(fn file -> File.rm!(Path.absname(file)) end)
  end

  defp assert_test(test) do
    IO.puts(" " <> test["desc"])

    result =
      ExMustache.parse(test["template"])
      |> ExMustache.render(test["data"])
      |> IO.iodata_to_binary()

    assert test["expected"] == result
  end
end
