class BooksController < ApplicationController
  before_action :require_login, except: [ :search_external ]
  before_action :set_book, only: [ :show, :edit, :update, :destroy ]

  def index
    @books = current_user.books.recent
    @books = @books.by_title(params[:search]) if params[:search].present?
    @search_query = params[:search]
  end

  def show
  end

  def new
    @book = current_user.books.build
  end

  def create
    @book = current_user.books.build(book_params)

    if @book.save
      redirect_to @book
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @book.update(book_params)
      redirect_to @book
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @book.destroy
    redirect_to books_path
  end

  def search_external
    query = params[:query]
    start_index = params[:start_index]&.to_i || 0
    max_results = 10

    if query.present?
      books_service = GoogleBooksService.new

      # 空のページをスキップして結果を取得
      collected_items = []
      current_start_index = start_index
      attempts = 0
      max_attempts = 5

      while collected_items.length < max_results && attempts < max_attempts
        search_results = books_service.search(query, current_start_index, max_results * 2)

        if search_results[:items].empty?
          break
        end

        remaining_needed = max_results - collected_items.length
        new_items = search_results[:items].take(remaining_needed)
        collected_items.concat(new_items)

        current_start_index += search_results[:items].length
        attempts += 1
      end

      if collected_items.empty?
        metadata_result = books_service.search(query, start_index, max_results)
        search_results = metadata_result
      else
        metadata_result = books_service.search(query, 0, 1)
        search_results = {
          items: collected_items,
          total_items: metadata_result[:total_items],
          start_index: start_index,
          items_per_page: max_results,
          api_total_items: metadata_result[:api_total_items],
          has_more_results: metadata_result[:has_more_results]
        }
      end

      current_page = (start_index / max_results) + 1
      actual_total_items = search_results[:total_items]
      max_google_items = 1000
      effective_total_items = [ actual_total_items, max_google_items ].min
      estimated_total_pages = (effective_total_items.to_f / max_results).ceil
      estimated_total_pages = [ estimated_total_pages, 1 ].max

      if collected_items.empty?
        if current_page == 1
          response_data = {
            items: [],
            pagination: {
              total_items: 0,
              start_index: start_index,
              items_per_page: max_results,
              current_page: current_page,
              total_pages: 0,
              has_next: false,
              has_prev: false,
              api_total_items: 0,
              is_last_page: true
            }
          }
        else
          response_data = {
            items: [],
            pagination: {
              total_items: start_index,
              start_index: start_index,
              items_per_page: max_results,
              current_page: current_page,
              total_pages: current_page - 1,
              has_next: false,
              has_prev: current_page > 1,
              api_total_items: search_results[:api_total_items],
              is_last_page: true,
              end_of_results: true
            }
          }
        end

        render json: response_data
        return
      end

      has_next = collected_items.length == max_results && start_index + max_results < effective_total_items
      has_prev = current_page > 1

      response_data = {
        items: collected_items,
        pagination: {
          total_items: effective_total_items,
          start_index: start_index,
          items_per_page: max_results,
          current_page: current_page,
          total_pages: estimated_total_pages,
          has_next: has_next,
          has_prev: has_prev,
          api_total_items: search_results[:api_total_items],
          is_last_page: !has_next
        }
      }

      render json: response_data
    else
      render json: {
        items: [],
        pagination: {
          total_items: 0,
          start_index: 0,
          items_per_page: max_results,
          current_page: 1,
          total_pages: 0,
          has_next: false,
          has_prev: false,
          api_total_items: 0,
          is_last_page: true
        }
      }
    end
  rescue => e
    Rails.logger.error "Error in search_external: #{e.class.name} - #{e.message}"

    render json: {
      items: [],
      pagination: {
        total_items: 0,
        start_index: 0,
        items_per_page: max_results,
        current_page: 1,
        total_pages: 0,
        has_next: false,
        has_prev: false,
        api_total_items: 0,
        is_last_page: true
      },
      error: "検索中にエラーが発生しました"
    }, status: 500
  end

  private

  def set_book
    @book = current_user.books.find(params[:id])
  end

  def book_params
    params.require(:book).permit(:title, :author, :publisher, :cover_image_url, :rating, :memo)
  end
end
