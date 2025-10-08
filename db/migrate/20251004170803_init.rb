class Init < ActiveRecord::Migration[7.1]
  def change
    
    create_table :users do |t|
      t.string :username, null: false
      t.string :email, null: false, index: { unique: true }
      t.string :password_digest, null: false
      t.timestamps
    end

    create_table :files do |t|
      t.references :user, null: false, foreign_key: true
      t.string :file_type, null: false  # "cv", "project", "evaluation"
      t.string :path, null: false
      t.timestamps
    end

    create_table :jobs do |t|
      t.string :status, null: false, default: "queued" # queued / processing / completed
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end

    create_table :job_details do |t|
      t.references :job, null: false, foreign_key: true
      t.references :file, null: false, foreign_key: true
      t.timestamps
    end

    create_table :results do |t|
      t.references :job, null: false, foreign_key: true
      t.float :cv_match_rate
      t.text :cv_feedback
      t.float :project_score
      t.text :project_feedback
      t.text :overall_summary
      t.timestamps
    end
  end
end
