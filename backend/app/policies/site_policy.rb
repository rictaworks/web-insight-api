class SitePolicy
  LIMIT = 10

  def initialize(user)
    @user = user
  end

  def create?
    @user.sites.count < LIMIT
  end
end
