class EvaluationsController < ApplicationController
  skip_before_action :verify_authenticity_token
  # before_action :authenticate_user!

  def create
    cv_id = params[:cv_file_id]
    project_id = params[:project_file_id]

    user = User.find_or_create_by!(email: "demo@example.com") do |u|
      u.username = "demo"
      u.password = SecureRandom.hex(8)
    end

    job = user.jobs.create!(status: "queued")

    JobDetail.create!(job: job, file_id: cv_id, role: "cv")
    JobDetail.create!(job: job, file_id: project_id, role: "project")
    EvaluateJob.perform_async(job.id)

    render json: { job_id: job.id, status: job.status }, status: :accepted
  end

  def show
    job = Job.find(params[:id])
    result = job.result

    render json: {
      job_id: job.id,
      status: job.status,
      error_message: job.error_message,
      result: result && {
        cv_match_rate: result.cv_match_rate,
        cv_feedback: result.cv_feedback,
        project_score: result.project_score,
        project_feedback: result.project_feedback,
        overall_summary: result.overall_summary,
        raw_llm_response: (result.raw_llm_response ? JSON.parse(result.raw_llm_response) : nil)
      }
    }
  end
end
