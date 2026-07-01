class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  before_create :assign_uuid

  private

  def assign_uuid
    pk = self.class.primary_key
    return unless pk

    col = self.class.columns_hash[pk]
    return if col && %i[string uuid].exclude?(col.type)

    self.id ||= SecureRandom.uuid
  end
end
