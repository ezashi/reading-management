require 'net/http'
require 'json'
require 'uri'

class GoogleBooksService
  BASE_URL = 'https://www.googleapis.com/books/v1/volumes'
  MAX_GOOGLE_BOOKS_RESULTS = 1000

  def initialize
    @api_key = Rails.application.credentials.google_books_api_key
    Rails.logger.info "=== Google Books Service Debug ==="
    Rails.logger.info "API key present: #{@api_key.present?}"
    if @api_key.present?
      Rails.logger.info "API key length: #{@api_key.length}"
      Rails.logger.info "API key preview: #{@api_key[0..3]}...#{@api_key[-4..-1]}"
    end
    Rails.logger.info "======================================"
  end

  def search(query, start_index = 0, max_results = 10)
    Rails.logger.info "=== Search Request Debug ==="
    Rails.logger.info "Query: '#{query}'"
    Rails.logger.info "Start index: #{start_index}"
    Rails.logger.info "Max results: #{max_results}"
    
    return empty_result(max_results) if query.blank?

    # APIキーがある場合は追加
    params = {
      q: query,
      startIndex: start_index,
      maxResults: max_results
    }
    params[:key] = @api_key if @api_key.present?

    uri = build_uri(params)
    Rails.logger.info "Request URL: #{uri}"

    begin
      response = make_request(uri)
      Rails.logger.info "Response code: #{response.code}"
      Rails.logger.info "Response headers: #{response.to_hash}"
      
      if response.code == '200'
        Rails.logger.info "Response body length: #{response.body.length}"
        Rails.logger.info "Response body preview: #{response.body[0..200]}..."
        
        data = JSON.parse(response.body)
        Rails.logger.info "Parsed data keys: #{data.keys}"
        Rails.logger.info "Total items: #{data['totalItems']}"
        Rails.logger.info "Items count: #{data['items']&.length || 0}"
        
        process_response(data, start_index, max_results)
      else
        Rails.logger.error "Google Books API Error: #{response.code} - #{response.message}"
        Rails.logger.error "Response body: #{response.body}" if response.body
        
        # エラーレスポンスを詳細に調査
        if response.body.present?
          begin
            error_data = JSON.parse(response.body)
            Rails.logger.error "Error details: #{error_data}"
          rescue JSON::ParserError
            Rails.logger.error "Could not parse error response as JSON"
          end
        end
        
        empty_result(max_results)
      end
    rescue JSON::ParserError => e
      Rails.logger.error "JSON Parse Error: #{e.message}"
      Rails.logger.error "Response body: #{response.body}"
      empty_result(max_results)
    rescue => e
      Rails.logger.error "Google Books API error: #{e.class.name} - #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(10).join("\n")}"
      empty_result(max_results)
    end
  end

  # シンプルなテスト用メソッド
  def test_connection
    Rails.logger.info "=== Testing Google Books API Connection ==="
    
    # 最もシンプルなクエリでテスト
    test_query = "ruby"
    params = { q: test_query, maxResults: 1 }
    params[:key] = @api_key if @api_key.present?
    
    uri = build_uri(params)
    Rails.logger.info "Test URL: #{uri}"
    
    begin
      response = make_request(uri)
      Rails.logger.info "Test response code: #{response.code}"
      
      if response.code == '200'
        data = JSON.parse(response.body)
        Rails.logger.info "Test successful - Total items: #{data['totalItems']}"
        return true
      else
        Rails.logger.error "Test failed - Response: #{response.body}"
        return false
      end
    rescue => e
      Rails.logger.error "Test error: #{e.message}"
      return false
    end
  end

  private

  def build_uri(params)
    query_string = params.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join('&')
    URI("#{BASE_URL}?#{query_string}")
  end

  def make_request(uri)
    Rails.logger.info "Making HTTP request to: #{uri.host}:#{uri.port}"
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 30

    # デバッグ用にSSL設定を表示
    Rails.logger.info "SSL settings: use_ssl=#{http.use_ssl}, verify_mode=#{http.verify_mode}"

    request = Net::HTTP::Get.new(uri)
    request['User-Agent'] = 'ReadingManagement/1.0'
    request['Accept'] = 'application/json'
    
    Rails.logger.info "Request headers: #{request.to_hash}"

    response = http.request(request)
    Rails.logger.info "Response received: #{response.class.name}"
    
    response
  end

  def process_response(data, start_index, max_results)
    items = data['items'] || []
    api_total_items = data['totalItems'] || 0

    Rails.logger.info "Processing response: #{items.length} items, totalItems: #{api_total_items}"

    actual_total_items = calculate_actual_total_items(api_total_items, start_index, items.length, max_results)

    formatted_items = format_results(items)
    Rails.logger.info "Formatted #{formatted_items.length} items"

    {
      items: formatted_items,
      total_items: actual_total_items,
      start_index: start_index,
      items_per_page: max_results,
      api_total_items: api_total_items,
      has_more_results: items.length == max_results && start_index + max_results < actual_total_items
    }
  end

  def format_results(items)
    items.map.with_index do |item, index|
      volume_info = item['volumeInfo'] || {}

      title = volume_info['title']
      authors = volume_info['authors']

      Rails.logger.debug "Item #{index}: #{title} by #{authors&.join(', ')}"

      {
        title: title || 'タイトル不明',
        authors: (authors || []).join(', '),
        publisher: volume_info['publisher'] || '出版社不明',
        cover_image: extract_cover_image(volume_info),
        description: volume_info['description'] || ''
      }
    end
  end

  def extract_cover_image(volume_info)
    image_links = volume_info['imageLinks'] || {}

    # 優先順位: smallThumbnail -> thumbnail -> small -> medium -> large
    %w[smallThumbnail thumbnail small medium large].each do |size|
      if image_links[size].present?
        # HTTPSに変換
        return image_links[size].gsub(/^http:/, 'https:')
      end
    end

    ''
  end

  def calculate_actual_total_items(api_total_items, start_index, current_items_count, max_results)
    if api_total_items > MAX_GOOGLE_BOOKS_RESULTS
      limited_total = MAX_GOOGLE_BOOKS_RESULTS
    else
      limited_total = api_total_items
    end

    if current_items_count < max_results && start_index > 0
      actual_total = start_index + current_items_count
      return [actual_total, limited_total].min
    end

    if current_items_count == 0 && start_index > 0
      return start_index
    end

    limited_total
  end

  def empty_result(max_results)
    Rails.logger.info "Returning empty result"
    {
      items: [],
      total_items: 0,
      start_index: 0,
      items_per_page: max_results,
      api_total_items: 0,
      has_more_results: false
    }
  end
end
