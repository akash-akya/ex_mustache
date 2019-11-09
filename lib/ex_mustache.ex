defmodule ExMustache do
  def tokenize(template) do
    template = do_tokenize(template, [], {"{{", "}}"})

    Enum.reverse([:end | template])
    |> chomp_newlines()
  end

  def do_tokenize(template, result, {start_tag, end_tag} = delimiters) do
    case find_start(template, start_tag) do
      {:newline, left, rest} ->
        do_tokenize(rest, [:newline | append(left, result)], delimiters)

      {:tag, left, rest} ->
        case find_end(rest, end_tag) do
          pos ->
            {interp, rest} = :erlang.split_binary(rest, pos)
            rest = binary_part(rest, byte_size(end_tag), byte_size(rest) - byte_size(end_tag))

            case tag(String.trim(interp)) do
              {:delimiter, {start_tag, end_tag}} = tag ->
                do_tokenize(rest, [tag | append(left, result)], {start_tag, end_tag})

              tag ->
                do_tokenize(rest, [tag | append(left, result)], delimiters)
            end

          :nomatch ->
            raise "Parsing Error. missing END tag. left: #{left} template: #{template}"
        end

      :nomatch ->
        append(template, result)
    end
  end

  defp find_start(string, start_tag) do
    with {pos, length} <- :binary.match(string, ["\n", start_tag]) do
      if binary_part(string, pos, length) == "\n" do
        {left, "\n" <> rest} = :erlang.split_binary(string, pos)
        {:newline, left, rest}
      else
        {left, rest} = :erlang.split_binary(string, pos)

        {:tag, left,
         binary_part(rest, byte_size(start_tag), byte_size(rest) - byte_size(start_tag))}
      end
    end
  end

  defp find_end(string, pattern, pos \\ 0)
  defp find_end(<<>>, _pattern, pos), do: pos

  defp find_end(<<_::utf8, rest::binary>> = string, pattern, pos) do
    if String.starts_with?(string, pattern) do
      if String.length(string) > String.length(pattern) do
        if String.slice(string, 1, String.length(pattern)) != pattern do
          pos
        else
          find_end(rest, pattern, pos + 1)
        end
      else
        pos
      end
    else
      find_end(rest, pattern, pos + 1)
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
      "=" <> field -> {:delimiter, find_delimiters(field)}
      "{" <> field -> {:unescape, triple_mustache_tag(String.trim(field), "}")}
      field when byte_size(field) > 0 -> {:variable, split_to_keys(field)}
      field -> raise("Invalid Tag: #{inspect(field)}")
    end
  end

  @delimiter_regex ~r/[[:space:]]*(?<start_tag>[[:graph:]]+)[[:space:]]+(?<end_tag>[[:graph:]]+)[[:space:]]*=/

  defp find_delimiters(field) do
    case Regex.named_captures(@delimiter_regex, field) do
      %{"start_tag" => start_tag, "end_tag" => end_tag} ->
        {start_tag, end_tag}

      _ ->
        raise "Invalid tag delimiter: #{field}"
    end
  end

  defp triple_mustache_tag(field, end_tag) do
    if String.ends_with?(field, end_tag) do
      String.slice(field, 0, String.length(field) - String.length(end_tag))
      |> String.trim()
      |> split_to_keys()
    else
      raise "unescape tag is not balanced"
    end
  end

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
                line =
                  if independent_partial?(line) do
                    reverse(line)
                    |> update_partial()
                    |> cleanup_line()
                  else
                    cleanup_line(line)
                    |> reverse()
                  end

                {[], true, [line | result]}
              else
                {[], true, [reverse(["\n" | line]) | result]}
              end

            :end ->
              if independent && !Enum.empty?(line) do
                line =
                  if independent_partial?(line) do
                    reverse(line)
                    |> update_partial()
                    |> cleanup_line()
                  else
                    cleanup_line(line)
                    |> reverse()
                  end

                {[], true, [line | result]}
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

            {:partial, field} ->
              {[{:partial, field, ""} | line], independent, result}

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

  defp independent_partial?(line) do
    partial_tags =
      Enum.filter(line, fn
        {:partial, _, _} -> true
        _ -> false
      end)
      |> Enum.count()

    partial_tags == 1
  end

  defp update_partial(line) do
    Enum.reduce(line, [], fn term, acc ->
      term =
        case term do
          {:partial, field, ""} -> {:partial, field, Enum.join(acc)}
          t -> t
        end

      [term | acc]
    end)
    |> Enum.reverse()
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

  defp dispatch([{:delimiter, _field} | template], acc, context) do
    dispatch(template, acc, context)
  end

  defp dispatch([{:partial, field, indent} | template], acc, context) do
    dispatch(template, [{:partial, field, indent} | acc], context)
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
          fn data, context, _partials ->
            fetch_value(data, var, context)
            |> serialize()
            |> html_escape()
          end

        {:partial, [field], indent} ->
          fn data, context, partials ->
            template =
              Map.get(partials, field, "")
              |> ExMustache.tokenize()

            template =
              if indent != "" do
                {_, template} =
                  Enum.reduce(template, {true, []}, fn term, {newline?, acc} ->
                    acc =
                      if newline? do
                        [term | [indent | acc]]
                      else
                        [term | acc]
                      end

                    newline? =
                      case term do
                        "\n" <> _ -> true
                        _ -> false
                      end

                    {newline?, acc}
                  end)

                Enum.reverse(template)
              else
                template
              end

            partial =
              template
              |> ExMustache.parse()
              |> ExMustache.create_template_func()

            rendered =
              ExMustache.render(partial, data, partials, context)
              |> IO.iodata_to_binary()
          end

        {:unescape, var} ->
          fn data, context, _partials ->
            fetch_value(data, var, context) |> serialize()
          end

        term when is_binary(term) ->
          fn _data, _context, _partials -> term end
      end
    end)
  end

  defp create_block_callback(keys, block) do
    block_callback = create_template_func(block)

    fn data, context, partials ->
      value = fetch_value(data, keys, context)

      case value do
        value when is_map(value) -> render(block_callback, value, partials, [data | context])
        [_ | _] -> Enum.map(value, &render(block_callback, &1, partials, [data | context]))
        [] -> []
        false -> []
        nil -> []
        _ -> render(block_callback, data, partials, context)
      end
    end
  end

  defp create_neg_block_callback(keys, block) do
    block_callback = create_template_func(block)

    fn data, context, partials ->
      value = fetch_value(data, keys, context)

      case value do
        [] -> render(block_callback, data, partials, context)
        false -> render(block_callback, data, partials, context)
        nil -> render(block_callback, data, partials, context)
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

  def render(template, data, partials, context) do
    Enum.map(template, fn callback ->
      callback.(data, context, partials)
    end)
  end
end
