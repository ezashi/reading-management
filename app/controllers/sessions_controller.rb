class SessionsController < ApplicationController
  def new
  end

  def create
    user = User.find_for_authentication(params[:login])

    if user && user.authenticate(params[:password])
      session[:user_id] = user.id
      redirect_to books_path
    else
      flash.now[:alert] = "ユーザー名/メールアドレスまたはパスワードが正しくありません"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session[:user_id] = nil
    redirect_to login_path
  end
end
