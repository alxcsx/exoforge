exclude =
  case :gen_tcp.connect(~c"127.0.0.1", 5432, [], 200) do
    {:ok, sock} ->
      :gen_tcp.close(sock)
      []

    {:error, _} ->
      [:postgres]
  end

ExUnit.start(exclude: exclude)
