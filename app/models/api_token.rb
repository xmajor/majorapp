class ApiToken < ActiveRecord::Base
  before_create :generate_token

  validates :name, presence: true
  validates :token, presence: true, uniqueness: true

  def regenerate_token
    update!(token: self.class.generate_unique_token)
  end

  def self.generate_unique_token
    loop do
      token = SecureRandom.hex(32)
      break token unless exists?(token: token)
    end
  end

  private

  def generate_token
    self.token = self.class.generate_unique_token
  end
end
