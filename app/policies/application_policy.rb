class ApplicationPolicy
  Result = Data.define(:success, :code, :context)

  attr_reader :user, :record

  def initialize(user:, record:)
    @user = user
    @record = record
  end

  private

  def allow
    Result.new(success: true, code: nil, context: {})
  end

  def deny(code, **context)
    Result.new(success: false, code: code, context: context)
  end
end
