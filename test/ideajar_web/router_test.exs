defmodule IdeajarWeb.RouterTest do
  use IdeajarWeb.ConnCase, async: true

  describe "GET /" do
    test "is dispatched to IdeajarWeb.IdeaLive.Index via the LiveView plug" do
      route = Phoenix.Router.route_info(IdeajarWeb.Router, "GET", "/", "localhost")

      assert route.plug == Phoenix.LiveView.Plug
      assert route.log_module == IdeajarWeb.IdeaLive.Index
      assert :require_auth in route.pipe_through
    end
  end
end
