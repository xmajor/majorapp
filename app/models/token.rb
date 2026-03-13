class Token < ActiveRecord::Base
  before_create :generate_token

  validates :token, presence: true, uniqueness: true

  private

  def generate_token
    self.token = loop do
      random_token = SecureRandom.hex(20)
      break random_token unless Token.exists?(token: random_token)
    end
  end
end
