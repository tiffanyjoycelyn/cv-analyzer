class AddErrorMessageToJobsAndLlmResponseToResults < ActiveRecord::Migration[8.0]
  def change
    add_column :jobs, :error_message, :text unless column_exists?(:jobs, :error_message)
    add_column :results, :raw_llm_response, :text unless column_exists?(:results, :raw_llm_response)
  end
end
