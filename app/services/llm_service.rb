require 'json'

class LlmService
  MAX_RETRIES = 3
  BACKOFF_BASE = 1.5

  def initialize(client: OpenAI::Client.new(api_key: ENV.fetch("OPENAI_API_KEY")))
    @client = client
  end

  def evaluate_cv(cv_text, context = "")
    prompt = build_cv_prompt(cv_text, context)
    content = call_with_retries(prompt)
    parsed = parse_llm_content(content, expected_keys: %w[cv_match_rate cv_feedback])
    validated = validate_llm_result(parsed, %w[cv_match_rate cv_feedback])

    {
      cv_match_rate: normalize_score(validated["cv_match_rate"] || validated[:cv_match_rate] || validated["match_rate"]),
      cv_feedback: (validated["cv_feedback"] || validated[:cv_feedback] || content.to_s[0..2000]),
      raw: content
    }
  end

  def evaluate_project(project_text, context = "")
    prompt = build_project_prompt(project_text, context)
    content = call_with_retries(prompt)
    parsed = parse_llm_content(content, expected_keys: %w[project_score project_feedback])
    validated = validate_llm_result(parsed, %w[project_score project_feedback])

    {
      project_score: normalize_score(validated["project_score"] || validated[:project_score] || validated["score"]),
      project_feedback: (validated["project_feedback"] || validated[:project_feedback] || content.to_s[0..2000]),
      raw: content
    }
  end

  def final_evaluation(cv_result, project_result)
    prompt = build_final_prompt(cv_result, project_result)
    content = call_with_retries(prompt)
    parsed = parse_llm_content(content, expected_keys: %w[overall_summary])
    validated = validate_llm_result(parsed, %w[overall_summary])

    {
      "overall_summary" => (validated["overall_summary"] || content.to_s[0..1000]),
      "raw" => content
    }
  end

  private

  def build_cv_prompt(cv_text, context)
    <<~PROMPT
    You are a technical recruiter evaluating a candidate's CV for a Backend Engineer position.

    Evaluate the candidate based on the job description and the scoring rubric below.

    ### Rubric for CV Evaluation
    1. Technical Skills Match (Weight: 40%)
       - Backend, databases, APIs, cloud, AI/LLM exposure.
       - 1 = Irrelevant | 2 = Few overlaps | 3 = Partial match | 4 = Strong match | 5 = Excellent + AI/LLM exposure
    2. Experience Level (Weight: 25%)
       - Years of experience and project complexity.
       - 1 = <1 yr | 2 = 1–2 yrs | 3 = 2–3 yrs | 4 = 3–4 yrs solid | 5 = 5+ yrs / high-impact
    3. Relevant Achievements (Weight: 20%)
       - Impact, measurable results, scope of contributions.
       - 1 = None | 2 = Minimal | 3 = Some outcomes | 4 = Strong impact | 5 = Major measurable impact
    4. Cultural / Collaboration Fit (Weight: 15%)
       - Communication, learning attitude, teamwork.
       - 1 = Poor | 2 = Minimal | 3 = Average | 4 = Good | 5 = Excellent

    ### Job Context
    #{context}

    ### Candidate CV
    #{cv_text}

    ### Output Instructions
    - Compute weighted average (1–5) → convert to 0–100 → `cv_match_rate`.
    - Write concise feedback (≤150 words) → `cv_feedback`.
    - Be objective, consistent, and avoid creative writing.
    - Return ONLY valid JSON (no markdown, no comments).

    Example output format:
    {
      "cv_match_rate": 85.5,
      "cv_feedback": "The candidate demonstrates strong backend skills in FastAPI and solid experience, but lacks clear achievements in AI projects."
    }
  PROMPT
  end

  def build_project_prompt(project_text, context)
    <<~PROMPT
    You are evaluating a candidate’s technical project submission for a Backend Engineer role.

    Assess the project based on the rubric below.

    ### Rubric for Project Evaluation
    1. Correctness (Prompt Design & Chaining) (Weight: 30%)
       - Implements prompt design, LLM chaining, and RAG context injection.
    2. Code Quality & Structure (Weight: 25%)
       - Clean, modular, reusable, tested.
    3. Resilience & Error Handling (Weight: 20%)
       - Handles retries, timeouts, randomness, and API failures gracefully.
    4. Documentation & Explanation (Weight: 15%)
       - README clarity, setup steps, trade-offs explained.
    5. Creativity / Bonus (Weight: 10%)
       - Extra features beyond requirements (authentication, dashboard, deployment, etc.)

    ### Case Study Context
    #{context}

    ### Candidate Project Report
    #{project_text}

    ### Output Instructions
    - Compute weighted average (1–5) → convert to 0–100 → `project_score`.
    - Write concise feedback (≤150 words) → `project_feedback`.
    - Return ONLY valid JSON (no markdown, no comments).

    Example output format:
    {
      "project_score": 92.0,
      "project_feedback": "Well-structured and resilient implementation. Demonstrates robust error handling and clear documentation."
    }
  PROMPT
  end

  def build_final_prompt(cv_result, project_result)
    <<~PROMPT
    You are an expert technical reviewer combining the candidate's CV and project evaluations.

    ### Your Task
    - Analyze both results holistically.
    - Provide:
      - `overall_summary`: 3–5 sentences summarizing strengths, weaknesses, and recommendations.

    ### CV Evaluation Result
    #{cv_result}

    ### Project Evaluation Result
    #{project_result}

    ### Output Instructions
    - Be concise, factual, and consistent.
    - Return ONLY valid JSON (no markdown, no commentary).

    Example output format:
    {
      "overall_summary": "The candidate has strong backend foundations and demonstrates solid implementation skills. Their project is technically sound, with clear documentation and resilience, though AI integration could be improved."
    }
  PROMPT
  end

  def call_with_retries(prompt)
    tries = 0
    temp = (ENV["LLM_TEMPERATURE"] || "0.2").to_f

    begin
      tries += 1
      Timeout.timeout(60) do
        response = @client.chat.completions.create(
          model: ENV.fetch("LLM_MODEL", "gpt-4o-mini"),
          messages: [{ role: "user", content: prompt }],
          temperature: temp,
          max_completion_tokens: 2000
        )
        content =
          if response.respond_to?(:choices)
            response.choices.first&.message&.content.to_s
          else
            response.dig("choices", 0, "message", "content").to_s
          end

        return content
      end

    rescue => e
      retriable = e.message =~ /(timeout|429|temporarily|reset|Rate)/i
      Rails.logger.warn("[WARNING] LLM call failed (attempt #{tries}): #{e.class}: #{e.message}")

      if tries >= MAX_RETRIES || !retriable
        Rails.logger.error("[ERROR]  Giving up after #{tries} attempts: #{e.message}")
        raise e
      end

      sleep(((BACKOFF_BASE**tries) * (1 + rand(0.2))).to_f)
      retry
    end
  end

  def parse_llm_content(content, expected_keys: [])
    return {} unless content
    stripped = content.strip

    begin
      json = JSON.parse(stripped)
      return json.is_a?(Hash) ? json : { "text" => json }
    rescue JSON::ParserError
      parsed = {}
      expected_keys.each do |k|
        if (m = stripped.match(/#{Regexp.escape(k)}\s*[:=-]\s*("?)([0-9]+\.?[0-9]*)(\1)/i))
          parsed[k] = m[2]
        elsif (m = stripped.match(/"#{Regexp.escape(k)}"\s*:\s*"([^"]+)"/i))
          parsed[k] = m[1]
        end
      end
      parsed["text"] = stripped if parsed.empty?
      parsed
    end
  end

  def validate_llm_result(hash, expected_keys)
    missing = expected_keys.reject { |k| hash.key?(k) }
    if missing.any?
      Rails.logger.warn("[WARNING]  Missing keys in LLM output: #{missing.join(', ')}")
      hash["validation_warning"] = "Missing keys: #{missing.join(', ')}"
    end
    if hash.values.all? { |v| v.nil? || v.to_s.strip.empty? }
      raise "[ERROR] Empty or invalid LLM response"
    end
    hash
  end

  def normalize_score(val)
    return 0.0 if val.nil?
    v = val.to_f
    v <= 5 && v > 0 ? ((v / 5.0) * 100.0).round(2) : v.round(2)
  end

  def compute_combined_from_results(cv_result, project_result)
    a = (cv_result[:cv_match_rate] || cv_result["cv_match_rate"] || 0).to_f
    b = (project_result[:project_score] || project_result["project_score"] || 0).to_f
    ((a + b) / 2.0).round(2)
  end
end
