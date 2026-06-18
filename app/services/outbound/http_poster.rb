require "net/http"

module Outbound
  # Thin Net::HTTP POST seam (stdlib — no added dependency). Isolated as its own
  # object so the delivery job can be tested by stubbing `.post` without a real
  # network or a webmock dependency. Network/timeout errors propagate to the
  # caller, which treats them as a transient delivery failure.
  class HttpPoster
    Response = Data.define(:code, :body)

    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    def self.post(url:, body:, headers:)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Post.new(uri)
      headers.each { |key, value| request[key] = value }
      request.body = body

      response = http.request(request)
      Response.new(code: response.code.to_i, body: response.body)
    end
  end
end
