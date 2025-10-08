class JobDetail < ApplicationRecord
  belongs_to :job
  belongs_to :file, class_name: "UploadedFile"
end
