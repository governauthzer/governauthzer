class Api::V1::BaseSerializer
  attr_reader :object, :options

  def initialize(object, **options)
    @object = object
    @options = options
  end

  def as_json
    raise NotImplementedError, "#{self.class.name} must implement #as_json"
  end

  def self.collection(records, **options)
    records.map { |record| new(record, **options).as_json }
  end
end
