class ApplicationService
  Result = Data.define(:success, :value, :code, :context)

  def self.call(...)
    new(...).call
  end

  def call
    raise NotImplementedError, "#{self.class.name} must implement #call"
  end

  private

  def success(value = nil)
    Result.new(success: true, value: value, code: nil, context: {})
  end

  def failure(code, **context)
    Result.new(success: false, value: nil, code: code, context: context)
  end
end
