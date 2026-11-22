require "test_helper"

class Notifications::MessengerDeliveryJobTest < ActiveJob::TestCase
  class FakePoster
    attr_reader :calls

    def initialize(&block)
      @block = block
      @calls = []
    end

    def post(**kwargs)
      @calls << kwargs
      @block.call(**kwargs)
    end
  end

  def setup
    @settings = NotificationSetting.create!(messenger_enabled: true,
                                            messenger_url: "https://hooks.example.com/T1/B2/secret",
                                            messenger_template: '{"text": "{{text}}", "kind": "{{event}}"}')
    @vars = { "text" => "Ada requested Member (Slack).", "event" => "review_requested" }
  end

  def teardown
    Notifications::MessengerDeliveryJob.http_poster = Outbound::HttpPoster
  end

  def with_poster(&block)
    Notifications::MessengerDeliveryJob.http_poster = FakePoster.new(&block)
  end

  def response(code, body = "") = Outbound::HttpPoster::Response.new(code: code, body: body)

  test "posts the rendered template as JSON to the saved URL and records success" do
    poster = with_poster { |**| response(200, "ok") }
    Notifications::MessengerDeliveryJob.perform_now(@vars)

    call = poster.calls.sole
    assert_equal "https://hooks.example.com/T1/B2/secret", call[:url]
    assert_equal({ "text" => "Ada requested Member (Slack).", "kind" => "review_requested" }, JSON.parse(call[:body]))
    assert_equal "application/json; charset=utf-8", call[:headers]["Content-Type"]

    @settings.reload
    assert_equal 200, @settings.messenger_last_response_code
    assert_nil @settings.messenger_last_error
  end

  test "a 4xx is recorded with the endpoint's answer and not retried" do
    with_poster { |**| response(403, "invalid_token") }
    assert_no_enqueued_jobs only: Notifications::MessengerDeliveryJob do
      Notifications::MessengerDeliveryJob.perform_now(@vars)
    end

    @settings.reload
    assert_equal 403, @settings.messenger_last_response_code
    assert_equal "HTTP 403: invalid_token", @settings.messenger_last_error
  end

  test "a 5xx is recorded and retried" do
    with_poster { |**| response(503, "unavailable") }
    assert_enqueued_with(job: Notifications::MessengerDeliveryJob) do
      Notifications::MessengerDeliveryJob.perform_now(@vars)
    end
    assert_equal 503, @settings.reload.messenger_last_response_code
  end

  test "a network error is recorded and retried" do
    with_poster { |**| raise Errno::ECONNREFUSED, "hooks.example.com" }
    assert_enqueued_with(job: Notifications::MessengerDeliveryJob) do
      Notifications::MessengerDeliveryJob.perform_now(@vars)
    end
    @settings.reload
    assert_nil @settings.messenger_last_response_code
    assert_match "ECONNREFUSED", @settings.messenger_last_error
  end

  test "a message queued before the channel was switched off is dropped" do
    poster = with_poster { |**| response(200) }
    @settings.update!(messenger_enabled: false)
    Notifications::MessengerDeliveryJob.perform_now(@vars)
    assert_empty poster.calls
  end

  test "the URL is read at delivery time, so a fixed URL applies to queued messages" do
    poster = with_poster { |**| response(200) }
    @settings.update!(messenger_url: "https://hooks.example.com/fixed")
    Notifications::MessengerDeliveryJob.perform_now(@vars)
    assert_equal "https://hooks.example.com/fixed", poster.calls.sole[:url]
  end
end
