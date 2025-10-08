class Job < ApplicationRecord
  belongs_to :user
  has_one :result, dependent: :destroy
  has_many :job_details, dependent: :destroy
  has_many :uploaded_files, through: :job_details, source: :file
end
