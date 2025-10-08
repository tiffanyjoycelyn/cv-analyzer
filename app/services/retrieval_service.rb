require 'httparty'

class RetrievalService
  QDRANT_URL = ENV.fetch("QDRANT_URL", "http://localhost:6333")

  def initialize(collection)
    @collection = collection
  end

  def search(vector, limit: 3)
    response = HTTParty.post(
      "#{QDRANT_URL}/collections/#{@collection}/points/search",
      headers: { "Content-Type" => "application/json" },
      body: {
        vector: vector,
        limit: limit
      }.to_json
    )

    unless response.success?
      raise "[ERROR] Qdrant search failed: #{response.body}"
    end

    parsed = JSON.parse(response.body)
    points = parsed.dig("result") || []

    if points.empty?
      puts "[WARN] No matching results found in Qdrant collection #{@collection}"
      return []
    end

    points.map { |r| r.dig("payload", "content") }.compact
  end
end
