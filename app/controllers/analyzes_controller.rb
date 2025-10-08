class AnalyzesController < ApplicationController
  skip_before_action :verify_authenticity_token
  # before_action :authenticate_user!

  def create
    file_id = params[:file_id]
    doc_type = params[:doc_type] || "cv"
    Rails.logger.info("⚙️ Analyze request: file_id=#{file_id}, doc_type=#{doc_type}")

    candidate_text = extract_text_from_file(file_id)
    embedding = Array.new(1536) { rand(-0.05..0.05) }
    collection = doc_type == "cv" ? "cv_chunks" : "project_chunks"
    retrieval = RetrievalService.new(collection)
    relevant_context = retrieval.search(embedding)

    llm = LlmService.new
    result =
      if doc_type == "cv"
        llm.evaluate_cv(candidate_text, relevant_context)
      else
        llm.evaluate_project(candidate_text, relevant_context)
      end

    render json: result
  rescue => e
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  def extract_text_from_file(file_id)
    "Sample candidate text for file_id #{file_id}"
  end
end
