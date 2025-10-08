require 'pdf-reader'
require 'httparty'
require 'json'
require_relative 'qdrant_service'

class DocumentIngestionService
  CHUNK_SIZE = 500

  def initialize(file_path, file_id, doc_type)
    @file_path = file_path
    @file_id = file_id
    @doc_type = doc_type
    collection_name = doc_type == "project" ? "project_chunks" : "cv_chunks"
    @qdrant = QdrantService.new(collection_name)
  end

  def ingest
    chunks.each_with_index do |chunk, i|
      embedding = mock_embedding(chunk)
      @qdrant.upsert(file_id: @file_id, chunk_index: i, embedding: embedding, content: chunk)
    end
  end

  private

  def chunks
    text = extract_text(@file_path)
    text.encode!('UTF-8', invalid: :replace, undef: :replace, replace: '')
    text.scan(/.{1,#{CHUNK_SIZE}}/m)
  end

  def extract_text(path)
    puts "[DEBUG] extract_text received input: #{path.inspect} (#{path.class})"

    reader = PDF::Reader.new(path)
    reader.pages.map(&:text).join("\n")
  rescue => e
    puts "[ERROR] in extract_text: #{e.message}"
    raise
  end

  # Use mock_embedding if quota already exceeded
  def mock_embedding(text)
    Array.new(1536) { rand(-0.05..0.05) }
  end
end
