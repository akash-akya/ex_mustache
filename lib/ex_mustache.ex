defmodule ExMustache do
  defstruct template: nil

  def tokenize(template), do: tokenize(template, []) |> Enum.reverse()

  def tokenize(template, result) do
    case :binary.match(template, ["{{"]) do
      {pos, _} ->
        {left, "{{" <> rest} = :erlang.split_binary(template, pos)

        case :binary.match(rest, ["}}"]) do
          {pos, _} ->
            {interp, "}}" <> right} = :erlang.split_binary(rest, pos)
            tokenize(right, [tag(String.trim(interp)) | [left | result]])

          :nomatch ->
            raise "Parsing Error. missing END tag. pos: #{pos} left: #{left} template: #{template}"
        end

      :nomatch ->
        [template | result]
    end
  end

  defp tag(field) do
    case field do
      "#" <> field -> {:block, split_to_keys(field)}
      "^" <> field -> {:neg_block, split_to_keys(field)}
      "/" <> field -> {:block_close, split_to_keys(field)}
      ">" <> field -> {:partial, split_to_keys(field)}
      "!" <> field -> {:comment, field}
      field when byte_size(field) > 0 -> {:variable, split_to_keys(field)}
      field -> raise("Invalid Tag: #{inspect(field)}")
    end
  end

  defp split_to_keys(field) do
    String.trim(field)
    |> String.split(".")
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

  defp dispatch([{:block, field} | template], acc, context) do
    {block, rest} = dispatch(template, [], [field | context])
    dispatch(rest, [{:block, field, Enum.reverse(block)} | acc], context)
  end

  defp dispatch([{:neg_block, field} | template], acc, context) do
    {block, rest} = dispatch(template, [], [field | context])
    dispatch(rest, [{:neg_block, field, block} | acc], context)
  end

  defp dispatch([{:block_close, field} | template], acc, [field | _context]) do
    {acc, template}
  end

  # template function

  def create_template_func(template) do
    Enum.map(template, fn t ->
      case t do
        {:block, var, block} ->
          create_block_callback(var, block)

        {:variable, var} ->
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

  defp fetch_value(data, keys, context) when is_map(data) do
    cond do
      Map.has_key?(data, hd(keys)) ->
        get_in(data, keys)

      Enum.empty?(context) ->
        raise "Value not found #{inspect(binding())}"

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

  # render

  def render(template, data, context \\ []) do
    Enum.map(template, fn callback ->
      callback.(data, context)
    end)
  end
end
