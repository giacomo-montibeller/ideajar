defmodule Ideajar.AuthTest do
  use ExUnit.Case, async: true

  alias Ideajar.Auth

  @configured_password Application.compile_env!(:ideajar, :workspace_password)

  describe "authenticate/2 (correctness)" do
    test "returns :ok when the submitted password matches the configured one" do
      assert :ok = Auth.authenticate(@configured_password, wrong_password_delay_ms: 0)
    end

    test "returns :error for a wrong password" do
      assert :error = Auth.authenticate("wrong", wrong_password_delay_ms: 0)
    end

    test "returns :error for an empty password" do
      assert :error = Auth.authenticate("", wrong_password_delay_ms: 0)
    end

    test "returns :error for nil" do
      assert :error = Auth.authenticate(nil, wrong_password_delay_ms: 0)
    end
  end

  describe "authenticate/2 (delay parameter)" do
    test "applies the configured delay on a wrong password" do
      {elapsed_us, :error} =
        :timer.tc(fn -> Auth.authenticate("wrong", wrong_password_delay_ms: 50) end)

      assert elapsed_us >= 50_000,
             "expected delay >= 50ms (50_000 µs), got #{elapsed_us} µs"

      assert elapsed_us < 200_000,
             "expected delay < 200ms (sanity bound), got #{elapsed_us} µs"
    end

    test "applies no delay on a correct password" do
      {elapsed_us, :ok} =
        :timer.tc(fn ->
          Auth.authenticate(@configured_password, wrong_password_delay_ms: 50)
        end)

      assert elapsed_us < 50_000,
             "correct password must not pay the wrong-password delay; got #{elapsed_us} µs"
    end

    test "delay 0 returns immediately on wrong password" do
      {elapsed_us, :error} =
        :timer.tc(fn -> Auth.authenticate("wrong", wrong_password_delay_ms: 0) end)

      assert elapsed_us < 50_000,
             "expected delay < 50ms with override 0; got #{elapsed_us} µs"
    end
  end
end
