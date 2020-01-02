defmodule ExMustache do
  defmodule TokenizeState do
    defstruct [:match_pattern, :close_pattern, :partials, :result, :line, :is_independent]
  end

  def parse(template) do
    {template, partials} = parse_template(template)
    {merge_strings(template), parse_partials(MapSet.to_list(partials), ".")}
  end

  defp parse_partials(partials, path, parsed \\ %{})
  defp parse_partials([], _path, parsed), do: parsed

  defp parse_partials([name | rest], path, parsed) do
    if Map.has_key?(parsed, name) do
      parse_partials(rest, path, parsed)
    else
      {template, new_partials} = parse_template(read_template_file(name, path))
      template = deep_reverse(template)
      parse_partials(rest ++ MapSet.to_list(new_partials), path, Map.put(parsed, name, template))
    end
  end

  defp read_template_file(name, _dir) do
    case File.read(name <> ".mustache") do
      {:ok, content} -> content
      {:error, :enoent} -> ""
    end
  end

  defp parse_template(template) do
    state = %TokenizeState{
      match_pattern: :binary.compile_pattern(["\n", "{{"]),
      close_pattern: :binary.compile_pattern(["}}"]),
      result: [],
      partials: MapSet.new(),
      line: [],
      is_independent: {true, nil}
    }

    %TokenizeState{result: template, partials: partials} = tokenize(template, state)

    template =
      Enum.reverse(template)
      |> dispatch([], [])

    {template, partials}
  end

  defp tokenize(template, state) do
    case split_string(template, state.match_pattern) do
      {:newline, left, rest} ->
        state =
          buffer_line(state, left <> "\n")
          |> dispatch_eol()

        tokenize(rest, state)

      {:tag, left, rest} ->
        case tag_close(rest, state.close_pattern) do
          {pos, length} ->
            {interp, rest} = :erlang.split_binary(rest, pos)
            rest = binary_part(rest, length, byte_size(rest) - length)
            tag = tag(String.trim(interp))

            state =
              case tag do
                {:delimiter, {start_delim, close_delim}} ->
                  %TokenizeState{
                    state
                    | match_pattern: :binary.compile_pattern(["\n", start_delim]),
                      close_pattern: :binary.compile_pattern([close_delim])
                  }

                {:partial, name, ""} ->
                  %TokenizeState{state | partials: MapSet.put(state.partials, name)}

                _ ->
                  state
              end

            tokenize(rest, buffer_line(state, left, tag))

          :nomatch ->
            raise "Parsing Error. missing END tag. left: #{left} template: #{template}"
        end

      :nomatch ->
        buffer_line(state, template)
        |> dispatch_eol()
    end
  end

  defp dispatch_eol(state) do
    if state.is_independent == {true, true} do
      line =
        if independent_partial?(state.line) do
          update_partial(Enum.reverse(state.line))
        else
          state.line
        end
        |> cleanup_line()

      %TokenizeState{state | line: line}
    else
      state
    end
    |> push_to_result()
  end

  defp buffer_line(%TokenizeState{} = state, ""), do: state

  defp buffer_line(%TokenizeState{} = state, item) do
    {empty_line, only_independent_tags} = state.is_independent

    is_independent =
      cond do
        empty_line == false || only_independent_tags == false ->
          {empty_line, only_independent_tags}

        is_binary(item) && !is_whitespace(item) ->
          {false, only_independent_tags}

        is_tuple(item) && elem(item, 0) in [:variable, :unescape] ->
          {empty_line, false}

        is_tuple(item) ->
          {empty_line, true}

        true ->
          {empty_line, only_independent_tags}
      end

    %TokenizeState{state | line: [item | state.line], is_independent: is_independent}
  end

  defp buffer_line(%TokenizeState{} = state, item1, item2) do
    buffer_line(buffer_line(state, item1), item2)
  end

  defp push_to_result(%TokenizeState{line: line, result: result} = state) do
    %TokenizeState{state | line: [], is_independent: {true, nil}, result: line ++ result}
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
      ">" <> field -> {:partial, String.trim(field), ""}
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

  defp split_to_keys("."), do: ["."]

  defp split_to_keys(field) do
    String.trim(field)
    |> String.split(".")
  end

  defp independent_partial?(line) do
    Enum.count(line, &match?({:partial, _, _}, &1)) == 1
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

  defp cleanup_line(line) do
    Enum.reject(line, &is_binary/1)
  end

  defp merge_strings(template) do
    {strings, acc} =
      Enum.reduce(template, {[], []}, fn
        item, {strings, acc} when is_binary(item) ->
          {[item | strings], acc}

        item, {strings, acc} ->
          acc =
            case item do
              {:block, field} ->
                [{:block, merge_strings(field)} | [IO.iodata_to_binary(strings) | acc]]

              {:neg_block, field} ->
                [{:neg_block, merge_strings(field)} | [IO.iodata_to_binary(strings) | acc]]

              item ->
                [item | [IO.iodata_to_binary(strings) | acc]]
            end

          {[], acc}
      end)

    [IO.iodata_to_binary(strings) | acc]
  end

  defp deep_reverse(template, result \\ [])
  defp deep_reverse([], result), do: result

  defp deep_reverse([term | template], result) when is_list(term) do
    deep_reverse(template, [deep_reverse(term) | result])
  end

  defp deep_reverse([term | template], result) do
    deep_reverse(template, [term | result])
  end

  defp is_whitespace(<<>>), do: true
  defp is_whitespace("\r" <> rest), do: is_whitespace(rest)
  defp is_whitespace("\n" <> rest), do: is_whitespace(rest)
  defp is_whitespace("\t" <> rest), do: is_whitespace(rest)
  defp is_whitespace(" " <> rest), do: is_whitespace(rest)
  defp is_whitespace(_), do: false

  # parser
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

      {:partial, name, indent} ->
        template = Map.fetch!(partials, name)

        if template do
          rendered = ExMustache.render({template, partials}, data, context)

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

      term when is_binary(term) ->
        term
    end
  end

  defp indent_lines(io_data, indent, result \\ [])

  defp indent_lines([], _indent, result), do: result

  defp indent_lines([term | io_data], indent, result) when is_binary(term) do
    result =
      if is_binary(term) && String.ends_with?(term, "\n") do
        [indent | [term | result]]
      else
        [term | result]
      end

    indent_lines(io_data, indent, result)
  end

  defp indent_lines([term | io_data], indent, result) when is_list(term) do
    indent_lines(io_data, indent, indent_lines(term, indent, result))
  end

  defp handle_block(keys, block, data, partials, context) do
    value = fetch_value(data, keys, context)

    case value do
      value when is_map(value) -> render({block, partials}, value, [data | context])
      [_ | _] -> Enum.map(value, &render({block, partials}, &1, [data | context]))
      [] -> []
      false -> []
      nil -> []
      _ -> render({block, partials}, data, context)
    end
  end

  defp handle_neg_block(keys, block, data, partials, context) do
    value = fetch_value(data, keys, context)

    case value do
      [] -> render({block, partials}, data, context)
      false -> render({block, partials}, data, context)
      nil -> render({block, partials}, data, context)
      _ -> []
    end
  end

  defp fetch_value(data, ["."], _context), do: data

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

  def render({template, partials}, data, context) do
    Enum.map(template, fn entity ->
      render_item(entity, data, partials, context)
    end)
  end
end
