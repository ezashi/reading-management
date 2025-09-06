namespace :google_books do
  desc "Check Google Books API configuration"
  task check_config: :environment do
    api_key = Rails.application.credentials.google_books_api_key

    if api_key.present?
      puts "✅ Google Books API key is configured"
      puts "   Key length: #{api_key.length} characters"
      puts "   Key preview: #{api_key[0..3]}...#{api_key[-4..-1]}"
    else
      puts "❌ Google Books API key is NOT configured"
      puts ""
      puts "To set up the API key:"
      puts "1. Run: rails credentials:edit"
      puts "2. Add: google_books_api_key: YOUR_API_KEY_HERE"
      puts "3. Save and close the file"
    end
  end

  desc "Test Google Books API connection"
  task test_api: :environment do
    service = GoogleBooksService.new
    result = service.search("ruby programming", 0, 1)

    if result[:items].any?
      puts "✅ Google Books API is working"
      puts "   Found #{result[:total_items]} total results"
      puts "   First result: #{result[:items].first[:title]}"
    else
      puts "❌ Google Books API test failed"
      puts "   No results returned"
    end
  rescue => e
    puts "❌ Google Books API test failed with error:"
    puts "   #{e.message}"
  end
end
