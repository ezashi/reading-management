require 'net/http'
require 'json'
require 'uri'

class GoogleBooksService
  BASE_URL = 'https://www.googleapis.com/books/v1/volumes'
  MAX_GOOGLE_BOOKS_RESULTS = 1000

  def initialize
    @api_key = Rails.application.credentials.google_books_api_key
    Rails.logger.info "Google Books Service initialized with API key: #{@api_key.present? ? 'Present' : 'Missing'}"
  end

  def search(query, start_index = 0, max_results = 10)
    return empty_result(max_results) if query.blank?

    # APIキーがある場合は追加
    params = {
      q: query,
      startIndex: start_index,
      maxResults: max_results
    }
    params[:key] = @api_key if @api_key.present?

    uri = build_uri(params)

    Rails.logger.info "Google Books API Request: #{uri}"

    begin
      response = make_request(uri)

      if response.code == '200'
        data = JSON.parse(response.body)
        process_response(data, start_index, max_results)
      else
        Rails.logger.error "Google Books API Error: #{response.code} - #{response.message}"
        Rails.logger.error "Response body: #{response.body}" if response.body
        empty_result(max_results)
      end
    rescue JSON::ParserError => e
      Rails.logger.error "JSON Parse Error: #{e.message}"
      empty_result(max_results)
    rescue => e
      Rails.logger.error "Google Books API error: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
      empty_result(max_results)
    end
  end

  private

  def build_uri(params)
    query_string = params.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join('&')
    URI("#{BASE_URL}?#{query_string}")
  end

  def make_request(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 30

    request = Net::HTTP::Get.new(uri)
    request['User-Agent'] = 'ReadingManagement/1.0'
    request['Accept'] = 'application/json'

    http.request(request)
  end

  def process_response(data, start_index, max_results)
    items = data['items'] || []
    api_total_items = data['totalItems'] || 0

    Rails.logger.info "API returned #{items.length} items, totalItems: #{api_total_items}"

    actual_total_items = calculate_actual_total_items(api_total_items, start_index, items.length, max_results)

    {
      items: format_results(items),
      total_items: actual_total_items,
      start_index: start_index,
      items_per_page: max_results,
      api_total_items: api_total_items,
      has_more_results: items.length == max_results && start_index + max_results < actual_total_items
    }
  end

  def format_results(items)
    items.map do |item|
      volume_info = item['volumeInfo'] || {}

      title = volume_info['title']
      authors = volume_info['authors']

      Rails.logger.debug "Processing book: #{title} by #{authors&.join(', ')}"

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
