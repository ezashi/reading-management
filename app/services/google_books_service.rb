require "net/http"
require "json"
require "uri"
require "cgi"
require "open-uri"
require "ostruct"

class GoogleBooksService
  BASE_URL = "https://www.googleapis.com/books/v1/volumes"
  MAX_GOOGLE_BOOKS_RESULTS = 1000

  def initialize
    @api_key = Rails.application.credentials.google_books_api_key
  end

  def search(query, start_index = 0, max_results = 10)
    begin
      return empty_result(max_results) if query.blank?

      if Rails.env.development? && ENV["USE_MOCK_BOOKS"] == "true"
        return mock_search_results(query, start_index, max_results)
      end

      if @api_key.blank?
        return {
          items: [],
          total_items: 0,
          start_index: 0,
          items_per_page: max_results,
          api_total_items: 0,
          has_more_results: false,
          error: "APIキーが設定されていません"
        }
      end

      improved_query = improve_search_query(query)

      params = {
        q: improved_query,
        startIndex: start_index,
        maxResults: max_results,
        key: @api_key,
        orderBy: "relevance",
        printType: "books",
        projection: "lite"
      }

      uri = build_uri(params)
      response = make_request(uri)

      if response.code == "200"
        begin
          data = JSON.parse(response.body)
          filtered_data = filter_search_results(data, query)
          process_response(filtered_data, start_index, max_results)
        rescue JSON::ParserError => e
          empty_result_with_error(max_results, "JSONの解析に失敗しました")
        end
      else
        error_message = "APIエラー: #{response.code}"
        if response.body.present?
          begin
            error_data = JSON.parse(response.body)
            if error_data["error"] && error_data["error"]["message"]
              error_message = error_data["error"]["message"]
            end
          rescue JSON::ParserError
          end
        end
        empty_result_with_error(max_results, error_message)
      end

    rescue Net::OpenTimeout, Net::ReadTimeout => e
      empty_result_with_error(max_results, "ネットワークタイムアウトが発生しました")
    rescue SocketError => e
      empty_result_with_error(max_results, "ネットワーク接続エラーが発生しました")
    rescue => e
      empty_result_with_error(max_results, "予期しないエラーが発生しました: #{e.message}")
    end
  end

  private

  def improve_search_query(query)
    cleaned_query = query.strip

    if cleaned_query =~ /[ひらがなカタカナ漢字]/
      "\"#{cleaned_query}\""
    elsif cleaned_query.include?(" ")
      words = cleaned_query.split(" ")
      if words.length <= 3
        "\"#{cleaned_query}\""
      else
        cleaned_query
      end
    else
      cleaned_query
    end
  end

  def filter_search_results(data, original_query)
    return data unless data["items"]

    query_words = original_query.downcase.split(/\s+/)

    filtered_items = data["items"].select do |item|
      volume_info = item["volumeInfo"] || {}
      title = volume_info["title"]&.downcase || ""
      authors = (volume_info["authors"] || []).join(" ").downcase
      description = volume_info["description"]&.downcase || ""
      categories = (volume_info["categories"] || []).join(" ").downcase

      searchable_text = "#{title} #{authors} #{description} #{categories}"
      relevance_score = calculate_relevance_score(searchable_text, query_words)

      relevance_score > 0
    end

    data.merge("items" => filtered_items)
  end

  def calculate_relevance_score(text, query_words)
    score = 0

    query_words.each do |word|
      if text.include?(word)
        score += 3
      end

      if text.include?(word[0..-2]) && word.length > 3
        score += 1
      end
    end

    score
  end

  def build_uri(params)
    query_string = params.map { |k, v| "#{k}=#{CGI.escape(v.to_s)}" }.join("&")
    URI("#{BASE_URL}?#{query_string}")
  end

  def make_request(uri)
    begin
      require "open-uri"

      response_body = URI.open(uri.to_s,
        "User-Agent" => "ReadingManagement/1.0",
        "Accept" => "application/json"
      ).read

      mock_response = OpenStruct.new(
        code: "200",
        message: "OK",
        body: response_body
      )

      mock_response

    rescue OpenURI::HTTPError => e
      error_response = OpenStruct.new(
        code: e.io.status.first,
        message: e.message,
        body: e.io.read
      )

      error_response

    rescue => e
      error_response = OpenStruct.new(
        code: "500",
        message: e.message,
        body: ""
      )

      error_response
    end
  end

  def process_response(data, start_index, max_results)
    items = data["items"] || []
    api_total_items = data["totalItems"] || 0

    effective_total_items = [ api_total_items, MAX_GOOGLE_BOOKS_RESULTS ].min
    current_page = (start_index / max_results) + 1
    actual_total_pages = (effective_total_items.to_f / max_results).ceil
    actual_total_pages = [ actual_total_pages, 1 ].max

    has_more_results = items.length == max_results &&
                       start_index + max_results < effective_total_items &&
                       current_page < actual_total_pages

    formatted_items = format_results(items)

    {
      items: formatted_items,
      total_items: effective_total_items,
      start_index: start_index,
      items_per_page: max_results,
      api_total_items: api_total_items,
      has_more_results: has_more_results,
      actual_total_pages: actual_total_pages
    }
  end

  def format_results(items)
    items.map.with_index do |item, index|
      volume_info = item["volumeInfo"] || {}

      title = volume_info["title"]
      authors = volume_info["authors"]
      publisher = volume_info["publisher"]
      cover_image = extract_cover_image(volume_info)
      description = volume_info["description"] || ""

      description = description.gsub(/<[^>]*>/, "").strip if description.present?

      {
        title: title || "タイトル不明",
        authors: (authors || []).join(", "),
        publisher: publisher || "出版社不明",
        cover_image: cover_image,
        description: description,
        isbn: extract_isbn(volume_info)
      }
    end
  end

  def extract_cover_image(volume_info)
    image_links = volume_info["imageLinks"] || {}

    image_priorities = %w[
      extraLarge
      large
      medium
      small
      thumbnail
      smallThumbnail
    ]

    image_priorities.each do |size|
      if image_links[size].present?
        image_url = image_links[size]
        image_url = image_url.gsub(/^http:/, "https:")

        if image_url.include?("books.google")
          unless image_url.include?("zoom=")
            image_url += image_url.include?("?") ? "&zoom=1" : "?zoom=1"
          end
          unless image_url.include?("edge=")
            image_url += "&edge=curl"
          end
        end

        return image_url
      end
    end

    isbn = extract_isbn(volume_info)
    if isbn.present?
      open_library_url = "https://covers.openlibrary.org/b/isbn/#{isbn}-M.jpg"
      return open_library_url
    end

    ""
  end

  def extract_isbn(volume_info)
    industry_identifiers = volume_info["industryIdentifiers"] || []

    isbn_13 = industry_identifiers.find { |id| id["type"] == "ISBN_13" }
    return isbn_13["identifier"] if isbn_13

    isbn_10 = industry_identifiers.find { |id| id["type"] == "ISBN_10" }
    return isbn_10["identifier"] if isbn_10

    nil
  end

  def empty_result_with_error(max_results, error_message)
    {
      items: [],
      total_items: 0,
      start_index: 0,
      items_per_page: max_results,
      api_total_items: 0,
      has_more_results: false,
      error: error_message
    }
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

  def mock_search_results(query, start_index, max_results)
    mock_books = [
      {
        title: "Rubyプログラミング入門",
        authors: "まつもとゆきひろ",
        publisher: "技術評論社",
        cover_image: "https://images.unsplash.com/photo-1516321318423-f06f85e504b3?w=128&h=180&fit=crop&crop=entropy&auto=format&q=80",
        description: "Rubyの入門書です"
      },
      {
        title: "Ruby on Rails Tutorial",
        authors: "Michael Hartl",
        publisher: "Addison-Wesley",
        cover_image: "https://images.unsplash.com/photo-1555066931-4365d14bab8c?w=128&h=180&fit=crop&crop=entropy&auto=format&q=80",
        description: "Ruby on Railsのチュートリアル"
      }
    ]

    filtered_books = if query.present?
      query_downcase = query.downcase
      mock_books.select { |book|
        book[:title].downcase.include?(query_downcase) ||
        book[:authors].downcase.include?(query_downcase) ||
        book[:publisher].downcase.include?(query_downcase) ||
        book[:description].downcase.include?(query_downcase)
      }
    else
      mock_books
    end

    paginated_books = filtered_books.slice(start_index, max_results) || []

    {
      items: paginated_books,
      total_items: filtered_books.length,
      start_index: start_index,
      items_per_page: max_results,
      api_total_items: filtered_books.length,
      has_more_results: start_index + max_results < filtered_books.length
    }
  end
end
