require "test_helper"

class DocsControllerTest < ActionDispatch::IntegrationTest
  test "GET /api-docs renders the Redoc page, no auth required" do
    get "/api-docs"

    assert_response :ok
    assert_match(/<redoc/, response.body)
    assert_includes response.body, api_docs_spec_path
  end

  test "GET /api-docs/v1.yaml serves the OpenAPI contract, no auth required" do
    get "/api-docs/v1.yaml"

    assert_response :ok
    assert_equal "application/yaml", response.media_type
    assert_match(/\Aopenapi:/, response.body)
    assert_includes response.body, "/sync/snapshots"
  end
end
