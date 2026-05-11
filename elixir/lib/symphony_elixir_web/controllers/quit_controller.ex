defmodule SymphonyElixirWeb.QuitController do
  @moduledoc """
  Shuts the Symphony BEAM node down on user request.

  Triggered by the Quit button in the root layout. Schedules `System.stop/1`
  on a separate process after sending the response so the browser receives
  the goodbye page before the VM exits.
  """

  use Phoenix.Controller, formats: [:html]

  require Logger

  @shutdown_delay_ms 250

  @spec quit(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def quit(conn, _params) do
    Logger.info("Symphony shutdown requested via web UI; halting in #{@shutdown_delay_ms}ms.")

    # Schedule the actual VM stop on a separate process so the response can
    # flush to the browser before we tear down the listening socket.
    spawn(fn ->
      Process.sleep(@shutdown_delay_ms)
      System.stop(0)
    end)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, goodbye_page())
  end

  defp goodbye_page do
    """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Symphony — Stopped</title>
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            color: #1f2937;
            background: #f3f4f6;
            display: flex;
            min-height: 100vh;
            align-items: center;
            justify-content: center;
            margin: 0;
          }
          .card {
            background: #fff;
            border: 1px solid #e5e7eb;
            border-radius: 12px;
            padding: 32px 40px;
            text-align: center;
            box-shadow: 0 6px 20px rgba(0,0,0,0.05);
            max-width: 440px;
          }
          h1 { margin: 0 0 8px; font-size: 22px; }
          p  { margin: 0; color: #6b7280; font-size: 14px; line-height: 1.5; }
          code { background: #f3f4f6; padding: 2px 6px; border-radius: 4px; font-size: 12px; }
        </style>
      </head>
      <body>
        <div class="card">
          <h1>Symphony stopped</h1>
          <p>
            The control plane has been shut down. To start it again, run
            <code>bash /tmp/symphony-local-run.sh &amp;</code> in a terminal.
          </p>
        </div>
      </body>
    </html>
    """
  end
end
