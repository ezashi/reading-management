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
    Rails.logger.info "Rails environment: #{Rails.env}"
    Rails.logger.info "USE_MOCK_BOOKS env var: #{ENV['USE_MOCK_BOOKS']}"
    Rails.logger.info "Mock condition: #{Rails.env.development? && ENV['USE_MOCK_BOOKS'] == 'true'}"
    
    return empty_result(max_results) if query.blank?

    # モックデータを使用する条件をチェック
    if Rails.env.development? && ENV['USE_MOCK_BOOKS'] == 'true'
      Rails.logger.info "=== Using Mock Data ==="
      return mock_search_results(query, start_index, max_results)
    end

    # 実際のAPI呼び出し
    Rails.logger.info "=== Making Real API Call ==="
    
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

  def mock_search_results(query, start_index, max_results)
    Rails.logger.info "=== Generating Mock Results ==="
    Rails.logger.info "Mock query: #{query}, start: #{start_index}, max: #{max_results}"
    
    mock_books = [
      # Ruby関連
      {
        title: "Rubyプログラミング入門",
        authors: "まつもとゆきひろ",
        publisher: "技術評論社",
        cover_image: "https://picsum.photos/128/180?random=1",
        description: "Rubyの入門書です"
      },
      {
        title: "Ruby on Rails Tutorial",
        authors: "Michael Hartl",
        publisher: "Addison-Wesley",
        cover_image: "https://picsum.photos/128/180?random=2",
        description: "Ruby on Railsのチュートリアル"
      },
      {
        title: "プログラミング言語Ruby",
        authors: "まつもとゆきひろ, David Flanagan",
        publisher: "オライリー・ジャパン",
        cover_image: "https://picsum.photos/128/180?random=3",
        description: "Rubyの詳細な解説書"
      },
      {
        title: "Effective Ruby",
        authors: "Peter J. Jones",
        publisher: "翔泳社",
        cover_image: "https://picsum.photos/128/180?random=4",
        description: "効果的なRubyプログラミング"
      },
      {
        title: "メタプログラミングRuby",
        authors: "Paolo Perrotta",
        publisher: "オライリー・ジャパン",
        cover_image: "https://picsum.photos/128/180?random=5",
        description: "Rubyのメタプログラミング"
      },
      {
        title: "Ruby レシピブック",
        authors: "青木峰郎",
        publisher: "ソフトバンク",
        cover_image: "https://picsum.photos/128/180?random=6",
        description: "Rubyのレシピ集"
      },
      # Rails関連
      {
        title: "Railsで学ぶWebアプリケーション開発",
        authors: "伊藤淳一",
        publisher: "技術評論社",
        cover_image: "https://picsum.photos/128/180?random=7",
        description: "RailsによるWebアプリ開発"
      },
      {
        title: "Rails Way",
        authors: "Obie Fernandez",
        publisher: "Addison-Wesley",
        cover_image: "https://picsum.photos/128/180?random=8",
        description: "Rails開発のベストプラクティス"
      },
      # Python関連
      {
        title: "Python入門",
        authors: "Python著者",
        publisher: "Python出版",
        cover_image: "https://picsum.photos/128/180?random=9",
        description: "Pythonの入門書"
      },
      {
        title: "Pythonクラッシュコース",
        authors: "Eric Matthes",
        publisher: "翔泳社",
        cover_image: "https://picsum.photos/128/180?random=10",
        description: "Python速習コース"
      },
      {
        title: "Effective Python",
        authors: "Brett Slatkin",
        publisher: "オライリー・ジャパン",
        cover_image: "https://picsum.photos/128/180?random=11",
        description: "効果的なPythonプログラミング"
      },
      # JavaScript関連
      {
        title: "JavaScript入門",
        authors: "JavaScript著者",
        publisher: "JavaScript出版",
        cover_image: "https://picsum.photos/128/180?random=12",
        description: "JavaScriptの基礎"
      },
      {
        title: "JavaScript: The Good Parts",
        authors: "Douglas Crockford",
        publisher: "オライリー・ジャパン",
        cover_image: "https://picsum.photos/128/180?random=13",
        description: "JavaScriptの良い部分"
      },
      {
        title: "モダンJavaScript入門",
        authors: "現代JS著者",
        publisher: "現代出版",
        cover_image: "https://picsum.photos/128/180?random=14",
        description: "現代的なJavaScript開発"
      },
      # その他のプログラミング
      {
        title: "Clean Code",
        authors: "Robert C. Martin",
        publisher: "Prentice Hall",
        cover_image: "https://picsum.photos/128/180?random=15",
        description: "きれいなコードの書き方"
      },
      {
        title: "プログラミング思考",
        authors: "思考著者",
        publisher: "思考出版",
        cover_image: "https://picsum.photos/128/180?random=16",
        description: "プログラミングの考え方"
      },
      # 日本の小説
      {
        title: "吾輩は猫である",
        authors: "夏目漱石",
        publisher: "岩波書店",
        cover_image: "https://picsum.photos/128/180?random=17",
        description: "夏目漱石の代表作"
      },
      {
        title: "こころ",
        authors: "夏目漱石",
        publisher: "新潮社",
        cover_image: "https://picsum.photos/128/180?random=18",
        description: "夏目漱石の名作"
      },
      {
        title: "羅生門",
        authors: "芥川龍之介",
        publisher: "角川書店",
        cover_image: "https://picsum.photos/128/180?random=19",
        description: "芥川龍之介の短編集"
      }
    ]

    # 検索フィルタリング
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

    Rails.logger.info "Total mock books: #{mock_books.length}"
    Rails.logger.info "Filtered books for query '#{query}': #{filtered_books.length}"

    # ページネーション
    paginated_books = filtered_books.slice(start_index, max_results) || []
    
    Rails.logger.info "Paginated books: #{paginated_books.length}"

    result = {
      items: paginated_books,
      total_items: filtered_books.length,
      start_index: start_index,
      items_per_page: max_results,
      api_total_items: filtered_books.length,
      has_more_results: start_index + max_results < filtered_books.length
    }
    
    Rails.logger.info "Mock result: #{result}"
    result
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