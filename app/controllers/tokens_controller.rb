class TokensController < ApplicationController
  def index
    @api_tokens = ApiToken.order(created_at: :desc)
  end

  def new
    @api_token = ApiToken.new
  end

  def create
    @api_token = ApiToken.new(token_params)
    if @api_token.save
      redirect_to api_tokens_path, notice: 'Token was successfully created.'
    else
      render :new
    end
  end

  def destroy
    @api_token = ApiToken.find(params[:id])
    @api_token.destroy
    redirect_to api_tokens_path, notice: 'Token was successfully revoked.'
  end

  def regenerate
    @api_token = ApiToken.find(params[:id])
    @api_token.regenerate_token
    redirect_to api_tokens_path, notice: 'Token was successfully regenerated.'
  end

  private

  def token_params
    params.require(:api_token).permit(:name)
  end
end
