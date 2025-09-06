require 'net/http'
require 'json'

class GoogleBooksService
  BASE_URL = 'https://www.googleapis.com/books/v1/volumes'
  MAX_GOOGLE_BOOKS_RESULTS = 1000

  def search(query, start_index = 0, max_results = 10)
    uri = URI("#{BASE_URL}?q=#{CGI.escape(query)}&startIndex=#{start_index}&maxResults=#{max_results}")

    begin
      response = Net::HTTP.get_response(uri)

      if response.code == '200'
        data = JSON.parse(response.body)
        items = data['items'] || []
        api_total_items = data['totalItems'] || 0

        actual_total_items = calculate_actual_total_items(api_total_items, start_index, items.length, max_results)

        {
          items: format_results(items),
          total_items: actual_total_items,
          start_index: start_index,
          items_per_page: max_results,
          api_total_items: api_total_items,
          has_more_results: items.length == max_results && start_index + max_results < actual_total_items
        }
      else
        {
          items: [],
          total_items: 0,
          start_index: 0,
          items_per_page: max_results,
          api_total_items: 0,
          has_more_results: false
        }
      end
    rescue => e
      Rails.logger.error "Google Books API error: #{e.message}"
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

  private

  def format_results(items)
    items.map do |item|
      volume_info = item['volumeInfo'] || {}

      {
        title: volume_info['title'] || 'タイトル不明',
        authors: (volume_info['authors'] || []).join(', '),
        publisher: volume_info['publisher'] || '出版社不明',
        cover_image: volume_info.dig('imageLinks', 'thumbnail') || '',
        description: volume_info['description'] || ''
      }
    end
  end

  def calculate_actual_total_items(api_total_items, start_index, current_items_count, max_results)
    # APIが返す総件数が非現実的に大きい場合は制限する
    if api_total_items > MAX_GOOGLE_BOOKS_RESULTS
      limited_total = MAX_GOOGLE_BOOKS_RESULTS
    else
      limited_total = api_total_items
    end

    if current_items_count < max_results && start_index > 0
      actual_total = start_index + current_items_count
      return [actual_total, limited_total].min
    end

    # 結果が空の場合
    if current_items_count == 0 && start_index > 0
      return start_index
    end

    limited_total
  end
end
