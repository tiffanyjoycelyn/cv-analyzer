# config/initializers/sidekiq.rb

if defined?(Sidekiq)
  require "sidekiq/rails"

  Sidekiq.configure_server do |config|

    config.on(:startup) do
      Rails.application.reloader.to_prepare do
        Rails.logger.info("[INFO] Sidekiq reloading Rails app code...")
      end
    end

    config.on(:quiet) do
      Rails.logger.info("Sidekiq is shutting down...")
    end
  end
end
