class FinalAnalysesController < ApplicationController
  skip_before_action :verify_authenticity_token
  # before_action :authenticate_user!

  def create
    cv_result = params[:cv_result] || {}
    project_result = params[:project_result] || {}

    llm = LlmService.new
    result = llm.final_evaluation(cv_result, project_result)

    user = User.first_or_create!(
      username: "demo_user",
      email: "demo@example.com",
      password: "password"
    )

    job = Job.create!(
      user: user,
      status: "completed"
    )

    Result.create!(
      job_id: job.id,
      cv_match_rate: extract_number(cv_result["cv_match_rate"]),
      cv_feedback: cv_result["cv_feedback"],
      project_score: extract_number(project_result["project_score"]),
      project_feedback: project_result["project_feedback"],
      overall_summary: result["overall_summary"]
    )

    render json: result
  rescue => e
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  def extract_number(value)
    return nil unless value
    value.to_s.gsub(/[^0-9.]/, "").to_f
  end
end