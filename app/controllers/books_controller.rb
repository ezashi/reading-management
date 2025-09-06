class BooksController < ApplicationController
  before_action :require_login
  before_action :set_book, only: [:show, :edit, :update, :destroy]

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
    query = params[:query]
    if query.present?
      # Google Books APIを使用した外部検索
      books_service = GoogleBooksService.new
      @search_results = books_service.search(query)
    else
      @search_results = []
    end

    render json: @search_results
  end

  private

  def set_book
    @book = current_user.books.find(params[:id])
  end

  def book_params
    params.require(:book).permit(:title, :author, :publisher, :cover_image_url, :rating, :memo)
  end
end
