# app/jobs/evaluate_job.rb
class EvaluateJob
  include Sidekiq::Job
  sidekiq_options queue: :evaluate, retry: 3

  def perform(job_id)
    job = Job.find(job_id)
    job.update!(status: "processing", error_message: nil)
    Rails.logger.info("🚀 EvaluateJob started for job_id=#{job.id}")

    begin
      # --- Retrieve related files ---
      cv_detail = job.job_details.find_by(role: "cv") || job.job_details.first
      project_detail = job.job_details.find_by(role: "project") || job.job_details.second

      cv_file = UploadedFile.find(cv_detail.file_id) rescue nil
      project_file = UploadedFile.find(project_detail.file_id) rescue nil
      raise "CV file missing" unless cv_file
      raise "Project file missing" unless project_file

      # --- Ingest candidate files (idempotent) ---
      [cv_file, project_file].each do |f|
        DocumentIngestionService.new(f.path, f.id.to_s, f.file_type).ingest
      end

      # --- Extract PDF text ---
      cv_text = extract_pdf_text(cv_file.path)
      project_text = extract_pdf_text(project_file.path)
      raise "Empty CV file" if cv_text.strip.empty?
      raise "Empty project file" if project_text.strip.empty?

      # --- Mock embeddings for RAG ---
      embedding_cv = Array.new(1536) { rand(-0.05..0.05) }
      embedding_project = Array.new(1536) { rand(-0.05..0.05) }

      # --- Retrieve RAG context from Qdrant ---
      job_desc_ctx = RetrievalService.new("job_description_chunks").search(embedding_cv) rescue []
      rubric_ctx = RetrievalService.new("rubric_chunks").search(embedding_cv) rescue []
      case_study_ctx = RetrievalService.new("case_study_chunks").search(embedding_project) rescue []

      cv_context = (job_desc_ctx + rubric_ctx).join("\n\n")
      project_context = (case_study_ctx + rubric_ctx).join("\n\n")

      # --- LLM evaluations ---
      llm = LlmService.new

      Rails.logger.info("🧠 Calling LLM for CV evaluation...")
      cv_result = safe_llm_call(job, "evaluate_cv") { llm.evaluate_cv(cv_text, cv_context) }

      Rails.logger.info("🧠 Calling LLM for Project evaluation...")
      project_result = safe_llm_call(job, "evaluate_project") { llm.evaluate_project(project_text, project_context) }

      Rails.logger.info("🧩 Synthesizing final evaluation...")
      final_result = safe_llm_call(job, "final_evaluation") { llm.final_evaluation(cv_result, project_result) }

      # --- Persist results ---
      Result.create!(
        job: job,
        cv_match_rate: cv_result[:cv_match_rate] || cv_result["cv_match_rate"],
        cv_feedback: cv_result[:cv_feedback] || cv_result["cv_feedback"],
        project_score: project_result[:project_score] || project_result["project_score"],
        project_feedback: project_result[:project_feedback] || project_result["project_feedback"],
        overall_summary: final_result["overall_summary"],
        raw_llm_response: {
          cv: cv_result[:raw],
          project: project_result[:raw],
          final: final_result[:raw],
          validation: [cv_result[:validation_warning], project_result[:validation_warning]].compact
        }.to_json
      )

      job.update!(status: "completed", error_message: nil)
      Rails.logger.info("✅ EvaluateJob completed successfully for job_id=#{job.id}")

    rescue => e
      # --- Error handling and job marking ---
      Rails.logger.error("💥 EvaluateJob failed job_id=#{job.id}: #{e.class}: #{e.message}")
      job.update!(status: "failed", error_message: e.message)

      begin
        Result.create!(
          job: job,
          raw_llm_response: { error: e.message, backtrace: e.backtrace.first(5) }.to_json
        )
      rescue => sub_e
        Rails.logger.error("⚠️ Failed to create Result record after job failure: #{sub_e.message}")
      end

      raise e
    end
  end

  private

  # --- Safe LLM execution wrapper ---
  def safe_llm_call(job, step_name, max_attempts: 3)
    attempts = 0
    begin
      attempts += 1
      yield
    rescue => e
      Rails.logger.warn("⚠️ LLM #{step_name} failed attempt #{attempts}: #{e.class}: #{e.message}")

      if attempts >= max_attempts
        msg = "LLM #{step_name} failed after #{attempts} attempts: #{e.message}"
        job.update!(error_message: msg)
        raise e
      end

      sleep(2**attempts)
      retry
    end
  end

  # --- PDF extraction ---
  def extract_pdf_text(file_path)
    reader = PDF::Reader.new(file_path)
    reader.pages.map(&:text).join("\n")
  rescue => e
    Rails.logger.error("❌ PDF text extraction failed: #{e.message}")
    raise
  end
end
