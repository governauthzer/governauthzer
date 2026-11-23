require "test_helper"

class DocsControllerTest < ActionDispatch::IntegrationTest
  test "GET /api-docs renders the Redoc page, no auth required" do
    get "/api-docs"

    assert_response :ok
    assert_match(/<redoc/, response.body)
    assert_includes response.body, api_docs_spec_path
  end

  test "the docs page loads scripts only from this origin" do
    get "/api-docs"

    srcs = css_select("script[src]").map { |s| s["src"] }
    assert_equal 1, srcs.size
    assert srcs.all? { |src| src.start_with?("/") && !src.start_with?("//") }, "external script: #{srcs.inspect}"

    get srcs.first
    assert_response :ok
    assert_includes response.body, "Redoc"
  end

  test "the docs page forbids loading anything from another origin" do
    get "/api-docs"
    csp = response.headers["Content-Security-Policy"].to_s
    assert_includes csp, "default-src 'self'"
    assert_includes csp, "script-src 'self';"
    assert_includes csp, "img-src 'self' data:"
  end

  test "GET /api-docs/v1.yaml serves the OpenAPI contract, no auth required" do
    get "/api-docs/v1.yaml"

    assert_response :ok
    assert_equal "application/yaml", response.media_type
    assert_match(/\Aopenapi:/, response.body)
    assert_includes response.body, "/sync/snapshots"
  end
end
