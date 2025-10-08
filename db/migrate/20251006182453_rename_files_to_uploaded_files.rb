class RenameFilesToUploadedFiles < ActiveRecord::Migration[8.0]
  def change
    rename_table :files, :uploaded_files
  end
end
