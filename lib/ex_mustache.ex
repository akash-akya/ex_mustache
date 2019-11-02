defmodule ExMustache do
  defstruct template: nil

  def tokenize(template) do
    template = do_tokenize(template, [])

    Enum.reverse([:end | template])
    |> chomp_newlines()
  end

  def do_tokenize(template, result) do
    case :binary.match(template, ["\n", "{{"]) do
      # newline
      {pos, 1} ->
        {left, "\n" <> rest} = :erlang.split_binary(template, pos)
        do_tokenize(rest, [:newline | append(left, result)])

      # open-tag
      {pos, 2} ->
        {left, "{{" <> rest} = :erlang.split_binary(template, pos)

        case :binary.match(rest, ["}}"]) do
          {pos, _} ->
            case :erlang.split_binary(rest, pos) do
              {interp, "}}}" <> right} ->
                do_tokenize(right, [
                  triple_mustache_tag(interp) | append(left, result)
                ])

              {interp, "}}" <> right} ->
                do_tokenize(right, [tag(String.trim(interp)) | append(left, result)])
            end

          :nomatch ->
            raise "Parsing Error. missing END tag. pos: #{pos} left: #{left} template: #{template}"
        end

      :nomatch ->
        append(template, result)
    end
  end

  defp tag(field) do
    case field do
      "#" <> field -> {:block, split_to_keys(field)}
      "^" <> field -> {:neg_block, split_to_keys(field)}
      "/" <> field -> {:block_close, split_to_keys(field)}
      ">" <> field -> {:partial, split_to_keys(field)}
      "!" <> field -> {:comment, field}
      "&" <> field -> {:unescape, split_to_keys(field)}
      field when byte_size(field) > 0 -> {:variable, split_to_keys(field)}
      field -> raise("Invalid Tag: #{inspect(field)}")
    end
  end

  defp triple_mustache_tag("{" <> field), do: {:unescape, split_to_keys(String.trim(field))}

  defp append(str, result) do
    case str do
      "" -> result
      str -> [str | result]
    end
  end

  defp split_to_keys("."), do: ["."]

  defp split_to_keys(field) do
    String.trim(field)
    |> String.split(".")
  end

  def chomp_newlines(template) do
    {[], true, result} =
      Enum.reduce(
        template,
        {[], true, []},
        fn term, {line, independent, result} ->
          case term do
            :newline ->
              if independent && !Enum.empty?(line) do
                {[], true, [reverse(cleanup_line(line)) | result]}
              else
                {[], true, [reverse(["\n" | line]) | result]}
              end

            :end ->
              if independent && !Enum.empty?(line) do
                {[], true, [reverse(cleanup_line(line)) | result]}
              else
                {[], true, [reverse(line) | result]}
              end

            term when is_binary(term) ->
              if String.trim(term) == "" do
                {[term | line], independent, result}
              else
                {[term | line], false, result}
              end

            {:variable, _} = term ->
              {[term | line], false, result}

            {:unescape, _} = term ->
              {[term | line], false, result}

            term ->
              {[term | line], independent, result}
          end
        end
      )

    Enum.reverse(result)
    |> Enum.flat_map(& &1)
  end

  defp reverse(line), do: Enum.reverse(line)

  defp cleanup_line(line) do
    Enum.reject(line, &is_binary/1)
  end

  # parser
  def parse(template) do
    dispatch(template, [], [])
    |> Enum.reverse()
  end

  defp dispatch([], acc, _context), do: acc

  defp dispatch([term | template], acc, context) when is_binary(term) do
    dispatch(template, [term | acc], context)
  end

  defp dispatch([{:variable, field} | template], acc, context) do
    dispatch(template, [{:variable, field} | acc], context)
  end

  defp dispatch([{:unescape, field} | template], acc, context) do
    dispatch(template, [{:unescape, field} | acc], context)
  end

  defp dispatch([{:block, field} | template], acc, context) do
    {block, rest} = dispatch(template, [], [field | context])
    dispatch(rest, [{:block, field, Enum.reverse(block)} | acc], context)
  end

  defp dispatch([{:neg_block, field} | template], acc, context) do
    {block, rest} = dispatch(template, [], [field | context])
    dispatch(rest, [{:neg_block, field, Enum.reverse(block)} | acc], context)
  end

  defp dispatch([{:block_close, field} | template], acc, [field | _context]) do
    {acc, template}
  end

  defp dispatch([{:comment, _field} | template], acc, context) do
    dispatch(template, acc, context)
  end

  # template function

  def create_template_func(template) do
    Enum.map(template, fn t ->
      case t do
        {:block, var, block} ->
          create_block_callback(var, block)

        {:neg_block, var, block} ->
          create_neg_block_callback(var, block)

        {:variable, var} ->
          fn data, context ->
            fetch_value(data, var, context)
            |> serialize()
            |> html_escape()
          end

        {:unescape, var} ->
          fn data, context ->
            fetch_value(data, var, context) |> serialize()
          end

        term when is_binary(term) ->
          fn _data, _context -> term end
      end
    end)
  end

  defp create_block_callback(keys, block) do
    block_callback = create_template_func(block)

    fn data, context ->
      value = fetch_value(data, keys, context)

      case value do
        value when is_map(value) -> render(block_callback, value, [data | context])
        [_ | _] -> Enum.map(value, &render(block_callback, &1, [data | context]))
        [] -> []
        false -> []
        nil -> []
        _ -> render(block_callback, data, context)
      end
    end
  end

  defp create_neg_block_callback(keys, block) do
    block_callback = create_template_func(block)

    fn data, context ->
      value = fetch_value(data, keys, context)

      case value do
        [] -> render(block_callback, data, context)
        false -> render(block_callback, data, context)
        nil -> render(block_callback, data, context)
        _ -> []
      end
    end
  end

  defp fetch_value(data, ["."], context), do: data

  defp fetch_value(data, keys, context) when is_map(data) do
    cond do
      Map.has_key?(data, hd(keys)) ->
        get_in(data, keys)

      Enum.empty?(context) ->
        # raise "Value not found #{inspect(binding())}"
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
      t -> ""
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

  # render

  def render(template, data, context \\ []) do
    Enum.map(template, fn callback ->
      callback.(data, context)
    end)
  end
end
