# frozen_string_literal: true

class AccountsController < ApplicationController
  before_action :require_authenticated_user!
  before_action :set_user

  # GET /account
  def show
    render Views::Accounts::Show.new(user: @user)
  end

  # GET /account/edit
  def edit
    render Views::Accounts::Edit.new(user: @user)
  end

  # PATCH/PUT /account
  def update
    if @user.update(account_params)
      redirect_to account_path, notice: t(".notice")
    else
      render Views::Accounts::Edit.new(user: @user),
             status: :unprocessable_content
    end
  end

  # DELETE /account
  def destroy
    @user.destroy!
    reset_session
    redirect_to root_path, notice: t(".notice")
  end

  private

  def set_user
    @user = current_user
  end

  def account_params
    params.expect(user: [:name])
  end
end
