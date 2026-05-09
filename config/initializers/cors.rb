Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Allow any origin to POST to the ingestion API — this is intentional.
    # The API key in the request body is the sole authentication mechanism.
    origins "*"

    resource "/api/v1/*",
      headers: :any,
      methods: %i[post options],
      max_age: 86_400
  end
end
