class FinalAnalysisService
  def synthesize(cv_result, project_result)
    match_rate = cv_result["cv_match_rate"].to_i
    project_score = project_result["project_score"].to_i

    average_score = ((match_rate + project_score) / 2.0).round

    summary = if average_score > 80
                "Outstanding candidate with strong technical alignment and analytical execution."
              elsif average_score > 60
                "Promising candidate with good fit. Could improve project communication or problem framing."
              else
                "Below expectations. Requires development in core skill alignment or project depth."
              end

    {
      overall_summary: summary,
    }
  end
end
