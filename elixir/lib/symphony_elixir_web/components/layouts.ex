defmodule SymphonyElixirWeb.Layouts do
  @moduledoc """
  Shared layouts for the observability dashboard.
  """

  use Phoenix.Component

  @spec root(map()) :: Phoenix.LiveView.Rendered.t()
  def root(assigns) do
    assigns = assign(assigns, :csrf_token, Plug.CSRFProtection.get_csrf_token())

    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={@csrf_token} />
        <title>Symphony Observability</title>
        <script defer src="/vendor/phoenix_html/phoenix_html.js"></script>
        <script defer src="/vendor/phoenix/phoenix.js"></script>
        <script defer src="/vendor/phoenix_live_view/phoenix_live_view.js"></script>
        <script>
          window.addEventListener("DOMContentLoaded", function () {
            var csrfToken = document
              .querySelector("meta[name='csrf-token']")
              ?.getAttribute("content");

            if (!window.Phoenix || !window.LiveView) return;

            var liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
              params: {_csrf_token: csrfToken}
            });

            liveSocket.connect();
            window.liveSocket = liveSocket;
          });
        </script>
        <link rel="stylesheet" href="/dashboard.css" />
      </head>
      <body style="margin: 0; padding-top: 44px;">
        <div style="position: fixed; top: 0; left: 0; right: 0; height: 36px; background: #111827; color: #e5e7eb; display: flex; align-items: center; justify-content: space-between; padding: 0 14px; z-index: 1000; font-family: -apple-system, BlinkMacSystemFont, sans-serif; font-size: 13px; box-shadow: 0 2px 6px rgba(0,0,0,0.2);">
          <div style="display: flex; align-items: center; gap: 16px;">
            <strong style="font-size: 14px; letter-spacing: 0.02em;">Symphony</strong>
            <a href="/" style="color: #d1d5db; text-decoration: none;">Dashboard</a>
            <a href="/projects" style="color: #d1d5db; text-decoration: none;">Projects</a>
            <a href="/providers" style="color: #d1d5db; text-decoration: none;">Providers</a>
          </div>
          <form method="post" action="/quit" onsubmit="return confirm('Shut Symphony down now?');" style="margin: 0;">
            <input type="hidden" name="_csrf_token" value={@csrf_token} />
            <button type="submit" style="background: #dc2626; color: white; border: 0; border-radius: 4px; padding: 5px 12px; font-size: 12px; font-weight: 600; cursor: pointer;">
              Quit
            </button>
          </form>
        </div>
        {@inner_content}
      </body>
    </html>
    """
  end

  @spec app(map()) :: Phoenix.LiveView.Rendered.t()
  def app(assigns) do
    ~H"""
    <main class="app-shell">
      {@inner_content}
    </main>
    """
  end
end
