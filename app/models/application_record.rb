class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  def audit_display
    respond_to?(:name) ? name : "#{self.class.name}##{id}"
  end
end
