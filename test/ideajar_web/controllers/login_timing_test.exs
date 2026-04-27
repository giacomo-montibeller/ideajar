defmodule IdeajarWeb.LoginTimingTest do
  # Acceptance: P1 — wrong-password submit responds in [500ms, 1500ms].
  # This file is intentionally `async: false` because it mutates the
  # application-wide :wrong_password_delay_ms env (other tests rely on the
  # test default of 0ms for speed).
  use IdeajarWeb.ConnCase, async: false

  setup do
    previous = Application.get_env(:ideajar, :wrong_password_delay_ms)
    Application.put_env(:ideajar, :wrong_password_delay_ms, 500)

    on_exit(fn ->
      Application.put_env(:ideajar, :wrong_password_delay_ms, previous)
    end)

    :ok
  end

  test "POST /login with wrong password responds in [500ms, 1500ms]", %{conn: conn} do
    {elapsed_us, response_conn} =
      :timer.tc(fn -> post(conn, "/login", %{"password" => "wrong"}) end)

    assert html_response(response_conn, 200) =~ "Password errata"

    assert elapsed_us >= 500_000,
           "expected response delay >= 500ms (500_000 µs), got #{elapsed_us} µs"

    assert elapsed_us <= 1_500_000,
           "expected response delay <= 1500ms (1_500_000 µs), got #{elapsed_us} µs"
  end
end
