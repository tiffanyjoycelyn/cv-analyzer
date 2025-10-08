class AddRoleToJobDetails < ActiveRecord::Migration[7.0]
  def change
    add_column :job_details, :role, :string unless column_exists?(:job_details, :role)
  end
end
