module Api::Sorting
  extend ActiveSupport::Concern

  class InvalidSortError < StandardError
    attr_reader :field

    def initialize(field)
      @field = field
      super("Invalid sort field: #{field}")
    end
  end

  included do
    rescue_from InvalidSortError do |e|
      render_error(
        code: "invalid_sort",
        status: :bad_request,
        message: e.message,
        details: { "field" => e.field }
      )
    end
  end

  def apply_sort(scope, whitelist:)
    return scope if params[:sort].blank?

    params[:sort].to_s.split(",").map(&:strip).reject(&:empty?).reduce(scope) do |acc, spec|
      direction = spec.start_with?("-") ? :desc : :asc
      field = spec.delete_prefix("-")
      raise InvalidSortError.new(field) unless whitelist.include?(field)
      acc.order(field => direction)
    end
  end
end
