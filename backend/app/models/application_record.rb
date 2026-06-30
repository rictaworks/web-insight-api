class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  before_create :assign_uuid

  private

  def assign_uuid
    pk = self.class.primary_key
    return unless pk && %i[string uuid].include?(self.class.columns_hash[pk]&.type)

    self.id ||= SecureRandom.uuid
  end
end
