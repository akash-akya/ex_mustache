defmodule ExMustache do
  defmodule TokenizeState do
    defstruct [:match_pattern, :close_pattern]
  end

  def tokenize(template) do
    state = %TokenizeState{
      match_pattern: :binary.compile_pattern(["\n", "{{"]),
      close_pattern: :binary.compile_pattern(["}}"])
    }

    template = do_tokenize(template, [], state)

    Enum.reverse([:end | template])
    |> chomp_newlines()
  end

  def do_tokenize(template, result, state) do
    case split_string(template, state.match_pattern) do
      {:newline, left, rest} ->
        do_tokenize(rest, [:newline | append(left, result)], state)

      {:tag, left, rest} ->
        case tag_close(rest, state.close_pattern) do
          {pos, length} ->
            {interp, rest} = :erlang.split_binary(rest, pos)
            rest = binary_part(rest, length, byte_size(rest) - length)

            case tag(String.trim(interp)) do
              {:delimiter, {start_delim, close_delim}} = tag ->
                state = %TokenizeState{
                  match_pattern: :binary.compile_pattern(["\n", start_delim]),
                  close_pattern: :binary.compile_pattern([close_delim])
                }

                do_tokenize(rest, [tag | append(left, result)], state)

              tag ->
                do_tokenize(rest, [tag | append(left, result)], state)
            end

          :nomatch ->
            raise "Parsing Error. missing END tag. left: #{left} template: #{template}"
        end

      :nomatch ->
        append(template, result)
    end
  end

  defp split_string(string, pattern) do
    with {pos, length} <- :binary.match(string, pattern) do
      if binary_part(string, pos, length) == "\n" do
        {left, "\n" <> rest} = :erlang.split_binary(string, pos)
        {:newline, left, rest}
      else
        {left, rest} = :erlang.split_binary(string, pos)
        {:tag, left, binary_part(rest, length, byte_size(rest) - length)}
      end
    end
  end

  defp tag_close(string, pattern) do
    with {pos, length} <- :binary.match(string, pattern) do
      index = pos + 1
      rest = binary_part(string, index, byte_size(string) - index)
      {pattern_occurrence(rest, pattern, pos), length}
    end
  end

  defp pattern_occurrence(<<_::utf8, rest::binary>> = string, pattern, index) do
    if String.starts_with?(string, pattern) do
      pattern_occurrence(rest, pattern, index + 1)
    else
      index
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
      "{" <> field -> {:unescape, triple_mustache_tag(field)}
      field when byte_size(field) > 0 -> {:variable, split_to_keys(field)}
      field -> raise("Invalid Tag: #{inspect(field)}")
    end
  end

  @delimiter_regex ~r/[[:space:]]*(?<start_delim>[[:graph:]]+)[[:space:]]+(?<close_delim>[[:graph:]]+)[[:space:]]*=/

  defp find_delimiters(field) do
    case Regex.named_captures(@delimiter_regex, field) do
      %{"start_delim" => start_delim, "close_delim" => close_delim} ->
        {start_delim, close_delim}

      _ ->
        raise "Invalid tag delimiter: #{field}"
    end
  end

  defp triple_mustache_tag(field) do
    if String.ends_with?(field, "}") do
      binary_part(field, 0, byte_size(field) - 1)
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
                    reverse(line)
                    |> cleanup_line()
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
                    reverse(line)
                    |> cleanup_line()
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
    |> merge_strings()
  end

  defp merge_strings(template) do
    Enum.reduce(template, [], fn
      item, [prev | acc] when is_binary(item) and is_binary(prev) ->
        [item <> prev | acc]

      {:block, field}, acc ->
        [{:block, merge_strings(field)} | acc]

      {:neg_block, field}, acc ->
        [{:neg_block, merge_strings(field)} | acc]

      item, acc ->
        [item | acc]
    end)
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

  defp render_item(item, data, partials, context) do
    case item do
      {:block, var, block} ->
        handle_block(var, block, data, partials, context)

      {:neg_block, var, block} ->
        handle_neg_block(var, block, data, partials, context)

      {:variable, var} ->
        fetch_value(data, var, context)
        |> serialize()
        |> html_escape()

      {:partial, [field], indent} ->
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

        partial = template |> ExMustache.parse()

        rendered =
          ExMustache.render(partial, data, partials, context)
          |> IO.iodata_to_binary()

      {:unescape, var} ->
        fetch_value(data, var, context) |> serialize()

      term when is_binary(term) ->
        term
    end
  end

  defp handle_block(keys, block, data, partials, context) do
    value = fetch_value(data, keys, context)

    case value do
      value when is_map(value) -> render(block, value, partials, [data | context])
      [_ | _] -> Enum.map(value, &render(block, &1, partials, [data | context]))
      [] -> []
      false -> []
      nil -> []
      _ -> render(block, data, partials, context)
    end
  end

  defp handle_neg_block(keys, block, data, partials, context) do
    value = fetch_value(data, keys, context)

    case value do
      [] -> render(block, data, partials, context)
      false -> render(block, data, partials, context)
      nil -> render(block, data, partials, context)
      _ -> []
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
    Enum.map(template, fn entity ->
      render_item(entity, data, partials, context)
    end)
  end
end
