defmodule ExMustacheTest do
  use ExUnit.Case

  test "opts" do
    Temp.track!()
    dir = Temp.mkdir!()
    :ok = File.write(Path.join(dir, "greetings.mustache"), "hello {{name}}", [:write])

    result =
      ExMustache.parse("message: {{>greetings}}", dir: dir)
      |> ExMustache.render(%{"name" => "world"})
      |> IO.iodata_to_binary()

    assert result == "message: hello world"
  end
end
