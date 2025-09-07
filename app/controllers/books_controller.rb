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
      flash[:notice] = "本を追加しました"
      redirect_to @book
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @book.update(book_params)
      flash[:notice] = "本の情報を更新しました"
      redirect_to @book
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @book.destroy
    flash[:notice] = "本を削除しました"
    redirect_to books_path
  end

  def search_external
    Rails.logger.info "=== Books Controller search_external ==="
    Rails.logger.info "Params: #{params.inspect}"
    Rails.logger.info "Session user_id: #{session[:user_id]}"
    Rails.logger.info "Current user present: #{current_user.present?}"

    query = params[:query]
    start_index = params[:start_index]&.to_i || 0
    max_results = 10

    Rails.logger.info "Query: '#{query}'"
    Rails.logger.info "Start index: #{start_index}"
    Rails.logger.info "Max results: #{max_results}"

    if query.present?
      books_service = GoogleBooksService.new
      Rails.logger.info "Created GoogleBooksService instance"

      search_results = books_service.search(query, start_index, max_results)
      Rails.logger.info "Search results from service: #{search_results.inspect}"

      current_page = (start_index / max_results) + 1
      total_pages = (search_results[:total_items].to_f / max_results).ceil

      is_last_page = search_results[:items].length < max_results ||
                     start_index + max_results >= search_results[:total_items]

      has_next = search_results[:has_more_results] && !is_last_page
      has_prev = start_index > 0

      if search_results[:items].empty? && current_page > 1
        total_pages = current_page - 1
        has_next = false
      end

      response_data = {
        items: search_results[:items],
        pagination: {
          total_items: search_results[:total_items],
          start_index: search_results[:start_index],
          items_per_page: search_results[:items_per_page],
          current_page: current_page,
          total_pages: total_pages,
          has_next: has_next,
          has_prev: has_prev,
          api_total_items: search_results[:api_total_items],
          is_last_page: is_last_page
        }
      }

      Rails.logger.info "Final response data: #{response_data.inspect}"

      render json: response_data
    else
      Rails.logger.info "Empty query, returning empty result"

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
    Rails.logger.error "Backtrace: #{e.backtrace.first(10).join("\n")}"

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
