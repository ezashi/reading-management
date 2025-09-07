require 'net/http'
require 'json'
require 'uri'
require 'cgi'
require 'open-uri'
require 'ostruct'

class GoogleBooksService
  BASE_URL = 'https://www.googleapis.com/books/v1/volumes'
  MAX_GOOGLE_BOOKS_RESULTS = 1000

  def initialize
    @api_key = Rails.application.credentials.google_books_api_key
    Rails.logger.info "=== Google Books Service Initialize ==="
    Rails.logger.info "API key present: #{@api_key.present?}"
    if @api_key.present?
      Rails.logger.info "API key length: #{@api_key.length}"
      Rails.logger.info "API key preview: #{@api_key[0..3]}...#{@api_key[-4..-1]}"
    end
    Rails.logger.info "========================================="
  end

  def search(query, start_index = 0, max_results = 10)
    Rails.logger.info "=== Search Request Debug ==="
    Rails.logger.info "Query: '#{query}'"
    Rails.logger.info "Start index: #{start_index}"
    Rails.logger.info "Max results: #{max_results}"
    Rails.logger.info "Rails environment: #{Rails.env}"
    Rails.logger.info "USE_MOCK_BOOKS env var: #{ENV['USE_MOCK_BOOKS']}"
    Rails.logger.info "Mock condition: #{Rails.env.development? && ENV['USE_MOCK_BOOKS'] == 'true'}"
    Rails.logger.info "API key present: #{@api_key.present?}"
    
    begin
      return empty_result(max_results) if query.blank?

      # モックデータを使用する条件をチェック
      if Rails.env.development? && ENV['USE_MOCK_BOOKS'] == 'true'
        Rails.logger.info "=== Using Mock Data ==="
        return mock_search_results(query, start_index, max_results)
      end

      # 実際のAPI呼び出し
      Rails.logger.info "=== Making Real API Call ==="
      
      # APIキーがない場合の処理
      if @api_key.blank?
        Rails.logger.error "API key is missing!"
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

      # 検索クエリを改善
      improved_query = improve_search_query(query)
      Rails.logger.info "Original query: '#{query}'"
      Rails.logger.info "Improved query: '#{improved_query}'"

      # パラメータ構築（検索精度向上のパラメータを追加）
      Rails.logger.info "Building API parameters..."
      params = {
        q: improved_query,
        startIndex: start_index,
        maxResults: max_results,
        key: @api_key,
        orderBy: 'relevance',  # 関連度順でソート
        printType: 'books',    # 本のみ（雑誌などを除外）
        projection: 'lite'     # 必要な情報のみ取得（高速化）
      }
      Rails.logger.info "Parameters: #{params.inspect.gsub(@api_key, '[API_KEY_HIDDEN]')}"

      # URI構築
      Rails.logger.info "Building URI..."
      uri = build_uri(params)
      Rails.logger.info "Request URL: #{uri.to_s.gsub(@api_key, '[API_KEY_HIDDEN]')}"

      # HTTPリクエスト実行
      Rails.logger.info "Making HTTP request..."
      response = make_request(uri)
      Rails.logger.info "Response code: #{response.code}"
      Rails.logger.info "Response message: #{response.message}"
      
      if response.code == '200'
        Rails.logger.info "Response body length: #{response.body.length}"
        Rails.logger.info "Response body preview: #{response.body[0..200]}..."
        
        begin
          data = JSON.parse(response.body)
          Rails.logger.info "Parsed data keys: #{data.keys}"
          Rails.logger.info "Total items: #{data['totalItems']}"
          Rails.logger.info "Items count: #{data['items']&.length || 0}"
          
          # 検索結果をフィルタリングして関連性を向上
          filtered_data = filter_search_results(data, query)
          
          return process_response(filtered_data, start_index, max_results)
        rescue JSON::ParserError => e
          Rails.logger.error "JSON Parse Error: #{e.message}"
          Rails.logger.error "Response body: #{response.body}"
          return empty_result_with_error(max_results, "JSONの解析に失敗しました")
        end
      else
        Rails.logger.error "Google Books API Error: #{response.code} - #{response.message}"
        Rails.logger.error "Response body: #{response.body}"
        
        # エラーレスポンスを詳細に調査
        error_message = "APIエラー: #{response.code}"
        if response.body.present?
          begin
            error_data = JSON.parse(response.body)
            Rails.logger.error "Error details: #{error_data}"
            if error_data['error'] && error_data['error']['message']
              error_message = error_data['error']['message']
            end
          rescue JSON::ParserError
            Rails.logger.error "Could not parse error response as JSON"
          end
        end
        
        return empty_result_with_error(max_results, error_message)
      end

    rescue Net::OpenTimeout => e
      Rails.logger.error "Network timeout error: #{e.message}"
      return empty_result_with_error(max_results, "ネットワークタイムアウトが発生しました")
    rescue Net::ReadTimeout => e
      Rails.logger.error "Read timeout error: #{e.message}"
      return empty_result_with_error(max_results, "読み込みタイムアウトが発生しました")
    rescue SocketError => e
      Rails.logger.error "Socket error: #{e.message}"
      return empty_result_with_error(max_results, "ネットワーク接続エラーが発生しました")
    rescue => e
      Rails.logger.error "Unexpected error: #{e.class.name} - #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(10).join("\n")}"
      return empty_result_with_error(max_results, "予期しないエラーが発生しました: #{e.message}")
    end
  end

  private

  # 検索クエリを改善するメソッドを追加
  def improve_search_query(query)
    # 特殊文字をエスケープ
    cleaned_query = query.strip
    
    # 日本語と英語が混在している場合の処理
    if cleaned_query =~ /[ひらがなカタカナ漢字]/
      # 日本語が含まれている場合、より厳密な検索
      "\"#{cleaned_query}\""
    elsif cleaned_query.include?(' ')
      # 複数の単語がある場合、すべての単語を含む結果を優先
      words = cleaned_query.split(' ')
      if words.length <= 3
        # 3語以下の場合は完全フレーズ検索
        "\"#{cleaned_query}\""
      else
        # 4語以上の場合は各単語で検索
        cleaned_query
      end
    else
      # 単一の単語の場合はそのまま
      cleaned_query
    end
  end

  # 検索結果をフィルタリングするメソッドを追加
  def filter_search_results(data, original_query)
    return data unless data['items']
    
    Rails.logger.info "Filtering search results for query: '#{original_query}'"
    
    query_words = original_query.downcase.split(/\s+/)
    Rails.logger.info "Query words: #{query_words}"
    
    filtered_items = data['items'].select do |item|
      volume_info = item['volumeInfo'] || {}
      title = volume_info['title']&.downcase || ''
      authors = (volume_info['authors'] || []).join(' ').downcase
      description = volume_info['description']&.downcase || ''
      categories = (volume_info['categories'] || []).join(' ').downcase
      
      # タイトル、著者、説明のいずれかに検索語が含まれているかチェック
      searchable_text = "#{title} #{authors} #{description} #{categories}"
      
      # 関連性スコアを計算
      relevance_score = calculate_relevance_score(searchable_text, query_words)
      
      Rails.logger.debug "Book: #{title} - Relevance score: #{relevance_score}"
      
      # スコアが0より大きい（何らかの関連性がある）場合のみ含める
      relevance_score > 0
    end
    
    Rails.logger.info "Filtered from #{data['items'].length} to #{filtered_items.length} items"
    
    # フィルタリング後のデータを返す
    data.merge('items' => filtered_items)
  end

  # 関連性スコアを計算するメソッド
  def calculate_relevance_score(text, query_words)
    score = 0
    
    query_words.each do |word|
      # 完全一致の場合は高スコア
      if text.include?(word)
        score += 3
      end
      
      # 部分一致の場合は低スコア
      if text.include?(word[0..-2]) && word.length > 3
        score += 1
      end
    end
    
    score
  end

  private

  def empty_result_with_error(max_results, error_message)
    Rails.logger.info "Returning empty result with error: #{error_message}"
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

  # シンプルなテスト用メソッド
  def test_connection
    Rails.logger.info "=== Testing Google Books API Connection ==="
    
    if @api_key.blank?
      Rails.logger.error "API key is missing for test"
      return false
    end
    
    # 最もシンプルなクエリでテスト
    test_query = "ruby"
    params = { q: test_query, maxResults: 1, key: @api_key }
    
    uri = build_uri(params)
    Rails.logger.info "Test URL: #{uri.to_s.gsub(@api_key, '[API_KEY_HIDDEN]')}"
    
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
    Rails.logger.info "Making HTTP request to: #{uri}"
    
    begin
      # 最もシンプルで確実なアプローチ
      require 'open-uri'
      
      Rails.logger.info "Using open-uri for HTTP request"
      
      # User-Agentヘッダーを設定してリクエスト
      response_body = URI.open(uri.to_s, 
        'User-Agent' => 'ReadingManagement/1.0',
        'Accept' => 'application/json'
      ).read
      
      Rails.logger.info "Response received successfully, length: #{response_body.length}"
      
      # レスポンスオブジェクトを模擬
      mock_response = OpenStruct.new(
        code: '200',
        message: 'OK',
        body: response_body
      )
      
      return mock_response

    rescue OpenURI::HTTPError => e
      Rails.logger.error "HTTP Error: #{e.message}"
      
      # エラーレスポンスを処理
      error_response = OpenStruct.new(
        code: e.io.status.first,
        message: e.message,
        body: e.io.read
      )
      
      return error_response

    rescue => e
      Rails.logger.error "Request failed: #{e.class.name} - #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
      
      # エラーレスポンスを作成
      error_response = OpenStruct.new(
        code: '500',
        message: e.message,
        body: ''
      )
      
      return error_response
    end
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

    # 画像がない場合は空文字を返す
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

  def mock_search_results(query, start_index, max_results)
    Rails.logger.info "=== Generating Mock Results ==="
    Rails.logger.info "Mock query: #{query}, start: #{start_index}, max: #{max_results}"
    
    mock_books = [
      # Ruby関連
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
      },
      {
        title: "プログラミング言語Ruby",
        authors: "まつもとゆきひろ, David Flanagan",
        publisher: "オライリー・ジャパン",
        cover_image: "https://images.unsplash.com/photo-1542831371-29b0f74f9713?w=128&h=180&fit=crop&crop=entropy&auto=format&q=80",
        description: "Rubyの詳細な解説書"
      },
      {
        title: "Effective Ruby",
        authors: "Peter J. Jones",
        publisher: "翔泳社",
        cover_image: "https://images.unsplash.com/photo-1544716278-ca5e3f4abd8c?w=128&h=180&fit=crop&crop=entropy&auto=format&q=80",
        description: "効果的なRubyプログラミング"
      },
      {
        title: "メタプログラミングRuby",
        authors: "Paolo Perrotta",
        publisher: "オライリー・ジャパン",
        cover_image: "https://images.unsplash.com/photo-1515879218367-8466d910aaa4?w=128&h=180&fit=crop&crop=entropy&auto=format&q=80",
        description: "Rubyのメタプログラミング"
      },
      {
        title: "Ruby レシピブック",
        authors: "青木峰郎",
        publisher: "ソフトバンク",
        cover_image: "https://images.unsplash.com/photo-1481627834876-b7833e8f5570?w=128&h=180&fit=crop&crop=entropy&auto=format&q=80",
        description: "Rubyのレシピ集"
      },
      # Python関連など（他の本も追加可能）
      {
        title: "Python入門",
        authors: "Python著者",
        publisher: "Python出版",
        cover_image: "https://images.unsplash.com/photo-1526379095098-d400fd0bf935?w=128&h=180&fit=crop&crop=entropy&auto=format&q=80",
        description: "Pythonの入門書"
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
end