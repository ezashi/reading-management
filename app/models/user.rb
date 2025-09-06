class User < ApplicationRecord
  has_secure_password

  has_many :books, dependent: :destroy

  validates :username, presence: true, uniqueness: true, length: { minimum: 3, maximum: 20 }
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 6 }, allow_nil: true

  # ユーザー名またはメールアドレスでの認証用
  def self.find_for_authentication(login)
    where("username = ? OR email = ?", login, login).first
  end
end
