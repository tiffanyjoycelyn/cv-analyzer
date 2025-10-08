class QdrantService
  include HTTParty
  base_uri ENV.fetch("QDRANT_URL", "http://localhost:6333")
  headers 'Content-Type' => 'application/json'

  def initialize(collection_name)
    @collection = collection_name
    ensure_collection
  end

  def ensure_collection
    response = self.class.get("/collections/#{@collection}")
    return if response.success?

    body = {
      vectors: { size: 1536, distance: "Cosine" }
    }

    response = self.class.put("/collections/#{@collection}", body: body.to_json)

    unless response.success?
      if response.parsed_response.dig("status", "error")&.include?("already exists")
        puts "[WARN] Collection '#{@collection}' already exists."
      else
        raise "[ERROR] Failed to create Qdrant collection: #{response.body}"
      end
    end
  end

  def upsert(file_id:, chunk_index:, embedding:, content:)
    body = {
      points: [
        { id: chunk_index, vector: embedding, payload: { file_id: file_id, chunk_index: chunk_index, content: content } }
      ]
    }

    response = self.class.put("/collections/#{@collection}/points", body: body.to_json)
    puts "[DEBUG] Qdrant response code: #{response.code}"
    puts "[DEBUG] Qdrant response body: #{response.body}"

    raise "[ERROR] Qdrant upsert failed: #{response.body}" unless response.success?
    response
  end
end
