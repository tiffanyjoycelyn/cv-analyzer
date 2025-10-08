class UploadedFile  < ApplicationRecord
  belongs_to :user
  has_many :job_details, dependent: :destroy
  has_many :jobs, through: :job_details
end
