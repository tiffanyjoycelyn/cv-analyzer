class IngestionsController < ApplicationController
  protect_from_forgery with: :null_session
  skip_before_action :verify_authenticity_token, only: [:create]
  before_action :authenticate_user!

  def create
    uploaded_io = params[:file]
    unless uploaded_io
      return render json: { error: "No file uploaded" }, status: :bad_request
    end

    doc_type = params[:doc_type] || determine_doc_type(uploaded_io.original_filename)

    file_id = SecureRandom.uuid
    storage_dir = Rails.root.join("storage/uploads")
    FileUtils.mkdir_p(storage_dir)
    persistent_path = storage_dir.join("#{file_id}_#{uploaded_io.original_filename}")

    File.open(persistent_path, "wb") { |f| f.write(uploaded_io.read) }

    user = User.find_or_create_by!(email: "demo@example.com") do |u|
      u.username = "demo"
      u.password = SecureRandom.hex(8)
    end

    uploaded_file = UploadedFile.create!(
      user: user,
      file_type: doc_type,
      path: persistent_path.to_s
    )

    render json: { message: "File ingested", file_id: uploaded_file.id, doc_type: doc_type }, status: :ok
  rescue => e
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  def determine_doc_type(filename)
    filename.downcase.include?("project") ? "project" : "cv"
  end
end
