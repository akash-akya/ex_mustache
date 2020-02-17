defmodule ExMustache.Renderer do
  @moduledoc false

  def render(template, partials, data), do: do_render(template, partials, data, [])

  def do_render(template, partials, data, context) do
    Enum.map(template, fn term ->
      render_tag(term, data, partials, context)
    end)
  end

  defp render_tag(term, data, partials, context) do
    case term do
      term when is_binary(term) ->
        term

      {:block, var, block} ->
        render_block(var, block, data, partials, context)

      {:neg_block, var, block} ->
        render_neg_block(var, block, data, partials, context)

      {:variable, var} ->
        fetch_value(data, var, context)
        |> serialize()
        |> html_escape()

      {:partial, name, indent} ->
        template = Map.fetch!(partials, name)

        if template do
          rendered = do_render(template, partials, data, context)

          if indent != "" do
            case indent_lines([indent | rendered], indent) do
              # trim indentation after last newline
              [^indent | rendered] -> rendered
              rendered -> rendered
            end
            |> Enum.reverse()
          else
            rendered
          end
        else
          ""
        end

      {:unescape, var} ->
        fetch_value(data, var, context) |> serialize()
    end
  end

  defp indent_lines(io_data, indent, result \\ [])

  defp indent_lines([], _indent, result), do: result

  defp indent_lines([term | io_data], indent, result) when is_binary(term) do
    result =
      if String.ends_with?(term, "\n") do
        [indent | [term | result]]
      else
        [term | result]
      end

    indent_lines(io_data, indent, result)
  end

  defp indent_lines([term | io_data], indent, result) when is_list(term) do
    indent_lines(io_data, indent, indent_lines(term, indent, result))
  end

  defp render_block(keys, block, data, partials, context) do
    value = fetch_value(data, keys, context)

    case value do
      value when is_map(value) -> do_render(block, partials, value, [data | context])
      [_ | _] -> Enum.map(value, &do_render(block, partials, &1, [data | context]))
      [] -> []
      false -> []
      nil -> []
      _ -> do_render(block, partials, data, context)
    end
  end

  defp render_neg_block(keys, block, data, partials, context) do
    value = fetch_value(data, keys, context)

    case value do
      [] -> do_render(block, partials, data, context)
      false -> do_render(block, partials, data, context)
      nil -> do_render(block, partials, data, context)
      _ -> []
    end
  end

  defp fetch_value(data, ["."], _context), do: data

  defp fetch_value(data, keys, context) when is_map(data) do
    cond do
      Map.has_key?(data, hd(keys)) ->
        get_in(data, keys)

      Enum.empty?(context) ->
        nil

      true ->
        fetch_value(hd(context), keys, tl(context))
    end
  end

  defp fetch_value(_data, _keys, _context), do: nil

  defp serialize(value) do
    case value do
      t when is_binary(t) -> t
      t when is_integer(t) -> to_string(t)
      t when is_number(t) -> to_string(t)
      _t -> ""
    end
  end

  defp html_escape(string, result \\ "")
  defp html_escape("", result), do: result
  defp html_escape("<" <> string, result), do: html_escape(string, result <> "&lt;")
  defp html_escape(">" <> string, result), do: html_escape(string, result <> "&gt;")
  defp html_escape("&" <> string, result), do: html_escape(string, result <> "&amp;")
  defp html_escape("\"" <> string, result), do: html_escape(string, result <> "&quot;")

  defp html_escape(<<c::utf8>> <> string, result) do
    html_escape(string, result <> <<c::utf8>>)
  end
end
