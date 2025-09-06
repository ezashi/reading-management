require 'net/http'
require 'json'

class GoogleBooksService
  BASE_URL = 'https://www.googleapis.com/books/v1/volumes'

  def search(query, max_results = 10)
    uri = URI("#{BASE_URL}?q=#{CGI.escape(query)}&maxResults=#{max_results}")

    begin
      response = Net::HTTP.get_response(uri)

      if response.code == '200'
        data = JSON.parse(response.body)
        format_results(data['items'] || [])
      else
        []
      end
    rescue => e
      Rails.logger.error "Google Books API error: #{e.message}"
      []
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
end
