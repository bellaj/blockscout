defmodule EthereumJSONRPC.Geth.Tracer do
  @moduledoc """
  Elixir implementation of a custom tracer (`priv/js/ethereum_jsonrpc/geth/debug_traceTransaction/tracer.js`)
  for variants that don't support specifying tracer in [debug_traceTransaction](https://github.com/ethereum/go-ethereum/wiki/Management-APIs#debug_tracetransaction) calls.
  """

  import EthereumJSONRPC, only: [integer_to_quantity: 1, quantity_to_integer: 1]

  def replay(logs) when is_list(logs) do
    ctx = %{
      stack: [],
#       call: %{
#         "type": "call",
#         "callType": "call",
#         "from": "0x866b3c4994e1416b7c738b9818b31dc246b95eee",
#         "to": "0xf105795bf5d1b1894e70bd04dc846898ab19fa62",
#         "input": "0xfebefd610000000000000000000000000000000000000000000000000000000000000040729c55462d0c341048710cb73b352a2f25e71d44b9c2960e7399e4ef1a8776c2000000000000000000000000000000000000000000000000000000000000000164220105bcf38287e81bb0b55702a2af9e50fdad695ae3197922d789de66e011",
#         "output": "0x",
#         "traceAddress": [],
#         "value": "0x2386f26fc10000",
#         "gas": nil,
#         "gasUsed": nil
#       },
      calls: [],
      depth: 1
    }

    logs
    |> Enum.map(fn log ->
      IO.inspect log
      log
    end)
    |> Enum.reduce(ctx, &step/2)
    |> result()
  end

  defp step(%{"error" => _}, %{stack: [%{"error" => _} | _]} = ctx), do: ctx

  defp step(%{"error" => _error}, ctx) do
    # TODO: putError()
    ctx
  end

  defp step(%{"depth" => log_depth} = log, %{depth: stack_depth, stack: [_call | stack]} = ctx) when log_depth < stack_depth do
    # TODO: beforeOp()
    step(log, %{ctx | stack: stack, depth: stack_depth - 1})
  end

  defp step(%{"op" => "CREATE"} = log, ctx), do: create_op(log, ctx)
  defp step(%{"op" => "SELFDESTRUCT"} = log, ctx), do: self_destruct_op(log, ctx)
  defp step(%{"op" => "CALL"} = log, ctx), do: call_op(log, "call", ctx)
  defp step(%{"op" => "CALLCODE"} = log, ctx), do: call_op(log, "callcode", ctx)
  defp step(%{"op" => "DELEGATECALL"} = log, ctx), do: call_op(log, "delegatecall", ctx)
  defp step(%{"op" => "STATICCALL"} = log, ctx), do: call_op(log, "staticcall", ctx)
  defp step(%{"op" => "REVERT"}, ctx), do: revert_op(ctx)
  defp step(_, ctx), do: ctx

  defp create_op(%{"stack" => log_stack, "memory" => log_memory, "gas" => log_gas}, %{depth: stack_depth, stack: stack} = ctx) do
    [stack_value, input_offset, input_length | _] = Enum.reverse(log_stack)

    init =
      log_memory
      |> IO.iodata_to_binary
      |> String.slice(quantity_to_integer("0x" <> input_offset) * 2, quantity_to_integer("0x" <> input_length) * 2)

    call = %{
      "type" => "create",
      "from" => "", # TODO
      "init" => "0x" <> init,
      "gas" => integer_to_quantity(log_gas),
      "value" => "0x" <> stack_value,
    }

    %{ctx | depth: stack_depth + 1, stack: [call | stack]}
  end

  defp self_destruct_op(_log, ctx) do
    # TODO
    ctx
  end

  defp call_op(%{"stack" => log_stack, "memory" => log_memory, "gas" => log_gas}, call_type, %{depth: stack_depth, stack: stack} = ctx) do
    [_, to | log_stack] = Enum.reverse(log_stack)

    {value, [input_offset, input_length, output_offset, output_length | _]} =
      case call_type do
        "delegatecall" -> {"", log_stack}
        "staticcall" -> {"0", log_stack}
        _ ->
          [value | rest] = log_stack
          {value, rest}
      end

    input =
      log_memory
      |> IO.iodata_to_binary
      |> String.slice(quantity_to_integer("0x" <> input_offset) * 2, quantity_to_integer("0x" <> input_length) * 2)

    call = %{
      "type" => "call",
      "callType" => call_type,
      "from" => "", # TODO
      "to" => "0x" <> String.slice(to, 24, 40),
      "input" => "0x" <> input,
      "outputOffset" => quantity_to_integer("0x" <> output_offset),
      "outputLength" => quantity_to_integer("0x" <> output_length),
      "gas" => integer_to_quantity(log_gas),
      "value" => "0x" <> value,
    }

    %{ctx | depth: stack_depth + 1, stack: [call | stack]}
  end

  defp revert_op(%{stack: [last | stack]} = ctx) do
    %{ctx | stack: [Map.put(last, :error, "execution reverted") | stack]}
  end

  defp result(_) do
    []
  end
end
