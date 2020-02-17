defmodule ExMustache do
  @moduledoc ~S"""
  ExMustache is a fast mustache templating library for Elixir.

  ExMustache supports everything except lambda from mustache spec.
  """

  defmodule Error do
    defexception [:message]
  end

  @type t :: %ExMustache{template: any(), partials: map()}
  defstruct [:template, :partials]

  @doc """
  Parse the binary and create template which can be used to render

  ## Options
    * `:dir` - directory where partial templates are located.
  """
  @spec parse(String.t(), keyword()) :: t()
  def parse(template, opts \\ []), do: ExMustache.Parser.parse(template, opts)

  @doc """
  Renders template by interpolating map data. Map keys *must* be string type.

  Returns [iodata](https://hexdocs.pm/elixir/IO.html#module-io-data).
  """
  @spec render(t(), map()) :: iodata()
  def render(%ExMustache{template: template, partials: partials}, map),
    do: ExMustache.Renderer.render(template, partials, map)
end
