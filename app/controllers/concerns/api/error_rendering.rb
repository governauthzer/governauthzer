module Api::ErrorRendering
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordNotFound do
      render_error(code: "not_found", status: :not_found, message: "Resource not found.")
    end

    rescue_from ActionController::ParameterMissing do |e|
      render_error(
        code: "parameter_missing",
        status: :bad_request,
        message: "Required parameter missing: #{e.param}.",
        details: { "param" => e.param.to_s }
      )
    end

    rescue_from ActiveRecord::RecordInvalid do |e|
      render_error(
        code: "validation_failed",
        status: :unprocessable_content,
        message: "Validation failed.",
        details: { "errors" => e.record.errors.messages.transform_keys(&:to_s) }
      )
    end

    rescue_from ActionController::UnpermittedParameters do |e|
      render_error(
        code: "unpermitted_parameters",
        status: :bad_request,
        message: "Unpermitted parameters: #{e.params.join(', ')}.",
        details: { "params" => e.params.map(&:to_s) }
      )
    end
  end

  def render_error(code:, status:, message:, details: nil)
    body = { "error" => { "code" => code, "message" => message } }
    body["error"]["details"] = details if details
    render json: body, status: status
  end
end
