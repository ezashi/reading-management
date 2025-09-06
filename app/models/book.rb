class Book < ApplicationRecord
  belongs_to :user

  validates :title, presence: true, length: { maximum: 255 }
  validates :rating, inclusion: { in: 1..5 }, allow_nil: true
  validates :memo, length: { maximum: 1000 }

  scope :by_title, ->(title) { where("title ILIKE ?", "%#{title}%") if title.present? }
  scope :recent, -> { order(created_at: :desc) }
end
