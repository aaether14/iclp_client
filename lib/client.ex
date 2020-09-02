defmodule Client do
    def init do
        pid = spawn_link(TcpClient, :init, [])
        serve(pid)
    end

    def serve(pid) do
        command = IO.gets ""
        unless command === "exit\n" do
            preprocessed_command = preprocess_command(command)
            send(pid, {:command, preprocessed_command})
            serve(pid)
        end
    end

    defp preprocess_command(command) do
        # in order to keep the protocol simple we match SEND commands and replace the message
        # between the quotes with its base64 representation
        Regex.replace(~r/SEND [[:alnum:] ]+ "(.*)"/, command, fn all, message ->
            encoded = Base.encode64(message)
            String.replace(all, ~s("#{message}"), encoded) end)
    end
end

defmodule TcpClient do
    @address '127.0.0.1'
    @port 8080

    def init do
        {:ok, socket} = :gen_tcp.connect(@address, @port, [:binary, active: true])
        serve(socket, <<>>)
    end

    def serve(socket, buffer) do
        receive do
            # we received a command that we need to forward to the server
            {:command, command} ->
                :gen_tcp.send(socket, command)
                serve(socket, buffer)
            # the rest of the code handles respones from the server
            # we only need to display server respones/notifications
            {:tcp, _, data} ->
                # process all available messages
                {new_buffer, messages} = parse_messages(buffer <> data, [])
                for m <- messages, do: IO.inspect m
                serve(socket, new_buffer)
            {:tcp_closed, _} ->
                IO.puts "The server has closed the connection."
                exit(:server_closed)
            {:tcp_error, _, reason} ->
                IO.puts "The server has encountered an error: #{reason}."
                exit(:server_error)
        end
    end

    defp parse_messages(<<packet_size :: 64, rest :: binary>>, messages) when byte_size(rest) >= packet_size do
        <<packet :: binary-size(packet_size), rest :: binary>> = rest
        case parse_message(packet) do
            {:ok, parsed} -> parse_messages(rest, [parsed] ++ messages)
            # if we can't parse a message, just display the error, then keep going
            {:error, parse_error} -> IO.inspect parse_error; parse_messages(rest, messages)
        end
    end
    defp parse_messages(buffer, messages) do
        {buffer, messages}
    end

    defp parse_message(input) do
        decoded = Jason.decode!(input)
        {:ok, case decoded do
            # we now need to decode the base64 content of messages
            %{"type" => "message", "content" => content} ->
                Map.put(decoded, "content", Base.decode64!(content))
            _ -> decoded
        end}
        rescue
            e -> {:error, e}
    end

end
