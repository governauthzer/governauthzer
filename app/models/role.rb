class Role < ApplicationRecord
  include Sluggable

  belongs_to :application
  belongs_to :approval_workflow, optional: true
  has_many :accesses, dependent: :restrict_with_error
  has_many :users, through: :accesses

  validates :name, presence: true
  validates :slug, uniqueness: { scope: :application_id }

  def operator_role?
    application.self_app?
  end
end
