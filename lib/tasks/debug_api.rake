namespace :debug do
  desc "Test Google Books API directly"
  task api_test: :environment do
    require 'net/http'
    require 'json'
    require 'cgi'

    api_key = Rails.application.credentials.google_books_api_key

    puts "=== API Key Check ==="
    puts "API Key present: #{api_key.present?}"
    puts "API Key length: #{api_key&.length}"
    puts ""

    if api_key.blank?
      puts "❌ API key is missing. Please run: rails credentials:edit"
      exit 1
    end

    puts "=== Testing API Connection ==="

    query = "ruby programming"
    url = "https://www.googleapis.com/books/v1/volumes?q=#{CGI.escape(query)}&maxResults=1&key=#{api_key}"

    puts "Request URL: #{url.gsub(api_key, '[API_KEY_HIDDEN]')}"

    begin
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30

      # 開発環境でのSSL検証を緩和
      if Rails.env.development?
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end

      request = Net::HTTP::Get.new(uri)
      request['User-Agent'] = 'ReadingManagement/1.0'

      puts "Making request..."
      response = http.request(request)

      puts "Response code: #{response.code}"
      puts "Response message: #{response.message}"

      if response.code == '200'
        data = JSON.parse(response.body)
        puts "✅ API Test successful!"
        puts "Total items found: #{data['totalItems']}"
        puts "Items returned: #{data['items']&.length || 0}"

        if data['items']&.any?
          first_book = data['items'].first['volumeInfo']
          puts "First book: #{first_book['title']} by #{first_book['authors']&.join(', ')}"
        end
      else
        puts "❌ API Test failed!"
        puts "Response body: #{response.body}"

        # エラーレスポンスを解析
        begin
          error_data = JSON.parse(response.body)
          if error_data['error']
            puts "Error message: #{error_data['error']['message']}"
            puts "Error code: #{error_data['error']['code']}"
          end
        rescue JSON::ParserError
          puts "Could not parse error response"
        end
      end

    rescue => e
      puts "❌ Request failed with error:"
      puts "Error: #{e.class.name} - #{e.message}"
      puts "Backtrace: #{e.backtrace.first(3).join("\n")}"
    end

    puts "\n=== Next Steps ==="
    if api_key.present?
      puts "1. Check Google Cloud Console:"
      puts "   - Books API is enabled"
      puts "   - API key restrictions"
      puts "   - Usage quotas"
      puts "2. Try the web interface search"
      puts "3. Check Rails logs for detailed information"
    else
      puts "1. Set up API key: rails credentials:edit"
      puts "2. Add: google_books_api_key: YOUR_API_KEY"
      puts "3. Run this test again"
    end
  end
end
