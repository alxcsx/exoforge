defmodule Exoforge.AuthRequestTest do
  use ExUnit.Case, async: true

  alias Exoforge.Auth.Request

  doctest Exoforge.Auth.Request

  describe "bearer/1" do
    test "accepts the Bearer prefix in any case" do
      assert Request.bearer([{"authorization", "Bearer abc123"}]) == "abc123"
      assert Request.bearer([{"authorization", "bearer abc123"}]) == "abc123"
      assert Request.bearer([{"authorization", "BEARER abc123"}]) == "abc123"
    end

    test "accepts a raw token with no scheme" do
      assert Request.bearer([{"authorization", "dev:developer"}]) == "dev:developer"
    end

    test "trims and rejects blank values" do
      assert Request.bearer([{"authorization", "  Bearer   abc123  "}]) == "abc123"
      assert Request.bearer([{"authorization", "   "}]) == nil
      assert Request.bearer([{"authorization", ""}]) == nil
    end

    test "is nil without an Authorization header" do
      assert Request.bearer([]) == nil
      assert Request.bearer([{"accept", "text/html"}]) == nil
      assert Request.bearer(nil) == nil
    end

    test "ignores header name casing" do
      assert Request.bearer([{"Authorization", "Bearer abc123"}]) == "abc123"
    end

    test "takes the first Authorization header" do
      assert Request.bearer([{"authorization", "Bearer first"}, {"authorization", "Bearer second"}]) ==
               "first"
    end
  end

  describe "token/3 precedence" do
    test "prefers the header over the query parameter over the cookie" do
      headers = [{"authorization", "Bearer from-header"}]
      params = %{"token" => "from-query"}
      cookies = %{"exo_auth_token" => "from-cookie"}

      assert Request.token(headers, params, cookies) == "from-header"
      assert Request.token([], params, cookies) == "from-query"
      assert Request.token([], %{}, cookies) == "from-cookie"
      assert Request.token([], %{}, %{}) == nil
    end

    test "falls through a blank header to the query parameter" do
      assert Request.token([{"authorization", ""}], %{"token" => "from-query"}, %{}) == "from-query"
    end

    test "tolerates missing maps" do
      assert Request.token(nil, nil, nil) == nil
    end
  end

  describe "cookie/1" do
    test "reads either cookie name, preferring the short one" do
      assert Request.cookie(%{"exo_auth_token" => "short"}) == "short"
      assert Request.cookie(%{"exoforge_auth_token" => "long"}) == "long"

      assert Request.cookie(%{"exo_auth_token" => "short", "exoforge_auth_token" => "long"}) ==
               "short"
    end

    test "rejects blank values and unknown names" do
      assert Request.cookie(%{"exo_auth_token" => "  "}) == nil
      assert Request.cookie(%{"some_other_cookie" => "x"}) == nil
      assert Request.cookie(nil) == nil
    end
  end

  describe "query/1 and header/2" do
    test "query reads the token parameter only" do
      assert Request.query(%{"token" => "abc"}) == "abc"
      assert Request.query(%{"access_token" => "abc"}) == nil
      assert Request.query(nil) == nil
    end

    test "header reads an arbitrary header, case-insensitively" do
      headers = [{"x-admin-token", "  secret  "}]

      assert Request.header(headers, "x-admin-token") == "secret"
      assert Request.header(headers, "X-Admin-Token") == "secret"
      assert Request.header(headers, "authorization") == nil
    end
  end
end
