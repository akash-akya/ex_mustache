defmodule ExMustache.Parser do
  @moduledoc false

  def parse(template, opts) do
    {template, partials} = parse_template(template)
    template = deep_reverse(template)

    %ExMustache{
      template: merge_strings(template),
      partials: parse_partials(MapSet.to_list(partials), Keyword.get(opts, :dir, "."))
    }
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

  defp read_template_file(name, dir) do
    case File.read(Path.join(dir, name <> ".mustache")) do
      {:ok, content} -> content
      {:error, :enoent} -> ""
    end
  end

  defmodule TokenizeState do
    @moduledoc false
    defstruct [:match_pattern, :close_pattern, :partials, :result, :line, :is_independent]
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
      |> compile([], [])

    {template, partials}
  end

  defp tokenize(template, state) do
    case split_string(template, state.match_pattern) do
      {:newline, left, rest} ->
        state =
          buffer_line(state, left <> "\n")
          |> collect_line()

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
            raise ExMustache.Error, message: "parser error: missing closing tag"
        end

      :nomatch ->
        buffer_line(state, template)
        |> collect_line()
    end
  end

  defp collect_line(state) do
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
      {match_repeated(rest, pattern, pos), length}
    end
  end

  defp match_repeated(<<_::utf8, rest::binary>> = string, pattern, index) do
    if String.starts_with?(string, pattern) do
      match_repeated(rest, pattern, index + 1)
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
      field -> raise ExMustache.Error, message: "parser error: Invalid tag: #{field}"
    end
  end

  @delimiter_regex ~r/[[:space:]]*(?<start_delim>[[:graph:]]+)[[:space:]]+(?<close_delim>[[:graph:]]+)[[:space:]]*=/
  defp find_delimiters(field) do
    case Regex.named_captures(@delimiter_regex, field) do
      %{"start_delim" => start_delim, "close_delim" => close_delim} ->
        {start_delim, close_delim}

      _ ->
        raise ExMustache.Error, message: "parser error: invalid delimiters tag: =#{field}"
    end
  end

  defp triple_mustache_tag(field) do
    if String.ends_with?(field, "}") do
      binary_part(field, 0, byte_size(field) - 1)
      |> String.trim()
      |> split_to_keys()
    else
      raise ExMustache.Error, message: "parser error: invalid triple mustache tag: {#{field}"
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
          merged = [IO.iodata_to_binary(Enum.reverse(strings)) | acc]

          acc =
            case item do
              {:block, fields, block} -> [{:block, fields, merge_strings(block)} | merged]
              {:neg_block, fields, block} -> [{:neg_block, fields, merge_strings(block)} | merged]
              item -> [item | merged]
            end

          {[], acc}
      end)

    [IO.iodata_to_binary(Enum.reverse(strings)) | acc]
    |> Enum.reverse()
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

  defp compile(tokens, context, result) do
    case tokens do
      [] ->
        result

      [term | template] when is_binary(term) ->
        compile(template, context, [term | result])

      [{:variable, field} | template] ->
        compile(template, context, [{:variable, field} | result])

      [{:unescape, field} | template] ->
        compile(template, context, [{:unescape, field} | result])

      [{:block, field} | template] ->
        {block, rest} = compile(template, [field | context], [])
        compile(rest, context, [{:block, field, Enum.reverse(block)} | result])

      [{:neg_block, field} | template] ->
        {block, rest} = compile(template, [field | context], [])
        compile(rest, context, [{:neg_block, field, Enum.reverse(block)} | result])

      [{:block_close, _field} | template] ->
        {result, template}

      [{:comment, _field} | template] ->
        compile(template, context, result)

      [{:delimiter, _field} | template] ->
        compile(template, context, result)

      [{:partial, field, indent} | template] ->
        compile(template, context, [{:partial, field, indent} | result])
    end
  end
end
