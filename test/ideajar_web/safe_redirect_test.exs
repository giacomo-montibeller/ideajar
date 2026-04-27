defmodule IdeajarWeb.SafeRedirectTest do
  use ExUnit.Case, async: true

  alias IdeajarWeb.SafeRedirect

  describe "normalize/1" do
    test "passes through a single-segment local path" do
      assert "/x" = SafeRedirect.normalize("/x")
    end

    test "passes through a multi-segment local path" do
      assert "/some/protected/path" = SafeRedirect.normalize("/some/protected/path")
    end

    test "passes through a path with a query string" do
      assert "/items?filter=cat" = SafeRedirect.normalize("/items?filter=cat")
    end

    test "rejects protocol-relative URLs" do
      assert "/" = SafeRedirect.normalize("//evil.com")
      assert "/" = SafeRedirect.normalize("//evil.com/path")
    end

    test "rejects absolute https URLs" do
      assert "/" = SafeRedirect.normalize("https://evil.com")
      assert "/" = SafeRedirect.normalize("https://evil.com/path")
    end

    test "rejects absolute http URLs" do
      assert "/" = SafeRedirect.normalize("http://evil.com")
    end

    test "rejects javascript: pseudo-URLs" do
      assert "/" = SafeRedirect.normalize("javascript:alert(1)")
    end

    test "rejects empty and nil" do
      assert "/" = SafeRedirect.normalize("")
      assert "/" = SafeRedirect.normalize(nil)
    end

    test "rejects values that do not start with a single forward slash" do
      assert "/" = SafeRedirect.normalize("relative/path")
      assert "/" = SafeRedirect.normalize("path")
    end

    test "rejects backslash-prefixed paths (legacy browser parsing quirk)" do
      assert "/" = SafeRedirect.normalize("/\\evil.com")
      assert "/" = SafeRedirect.normalize("/\\\\evil.com")
    end

    test "rejects paths containing CR or LF (defense-in-depth on header injection)" do
      assert "/" = SafeRedirect.normalize("/safe\r\nLocation: https://evil.com")
      assert "/" = SafeRedirect.normalize("/safe\nfoo")
      assert "/" = SafeRedirect.normalize("/safe\rfoo")
    end
  end
end
