defmodule Ideajar.ConfigTest do
  use ExUnit.Case, async: true

  alias Ideajar.Config

  describe "validate!/1" do
    test "returns :ok with valid workspace_password and secret_key_base" do
      assert :ok =
               Config.validate!(
                 workspace_password: "long-enough-password",
                 secret_key_base: String.duplicate("a", 64)
               )
    end

    test "raises naming WORKSPACE_PASSWORD when workspace_password is nil" do
      assert_raise RuntimeError, ~r/WORKSPACE_PASSWORD/, fn ->
        Config.validate!(
          workspace_password: nil,
          secret_key_base: String.duplicate("a", 64)
        )
      end
    end

    test "raises with min-length hint when workspace_password is below 12 chars" do
      assert_raise RuntimeError, ~r/at least 12/, fn ->
        Config.validate!(
          workspace_password: "11charssss_",
          secret_key_base: String.duplicate("a", 64)
        )
      end
    end

    test "accepts workspace_password at the 12-char boundary" do
      assert :ok =
               Config.validate!(
                 workspace_password: String.duplicate("a", 12),
                 secret_key_base: String.duplicate("b", 64)
               )
    end

    test "raises naming SECRET_KEY_BASE when secret_key_base is nil" do
      assert_raise RuntimeError, ~r/SECRET_KEY_BASE/, fn ->
        Config.validate!(
          workspace_password: "long-enough-password",
          secret_key_base: nil
        )
      end
    end

    test "raises with min-length hint when secret_key_base is below 64 bytes" do
      assert_raise RuntimeError, ~r/at least 64/, fn ->
        Config.validate!(
          workspace_password: "long-enough-password",
          secret_key_base: String.duplicate("a", 63)
        )
      end
    end

    test "accepts secret_key_base at the 64-byte boundary" do
      assert :ok =
               Config.validate!(
                 workspace_password: "long-enough-password",
                 secret_key_base: String.duplicate("a", 64)
               )
    end
  end
end
