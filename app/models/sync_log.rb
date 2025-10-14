class SyncLog < ApplicationRecord
  validates :table_name, presence: true
  validates :synced_at, presence: true

  scope :recent, -> { order(synced_at: :desc).limit(10) }
  scope :successful, -> { where(error_message: nil) }
  scope :failed, -> { where.not(error_message: nil) }

  def successful?
    error_message.nil?
  end

  def failed?
    !successful?
  end
end
