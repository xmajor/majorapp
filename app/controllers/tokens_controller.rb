class TokensController < ApplicationController
  def index
    @tokens = Token.all
  end

  def new
    @token = Token.new
  end

  def create
    @token = Token.new(token_params)
    if @token.save
      redirect_to tokens_path, notice: 'Token was successfully created.'
    else
      render :new
    end
  end

  def destroy
    @token = Token.find(params[:id])
    @token.destroy
    redirect_to tokens_path, notice: 'Token was successfully deleted.'
  end

  private

  def token_params
    params.require(:token).permit(:description)
  end
end
