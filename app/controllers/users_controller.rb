# frozen_string_literal: true

# Source: https://github.com/rails/rails/blob/7-1-stable/railties/lib/rails/generators/rails/scaffold_controller/templates/controller.rb.tt
class UsersController < ApplicationController
  before_action :require_authenticated_user!
  before_action :set_user, only: %i[show edit update destroy]
  before_action :authorize_user!

  # GET /users
  def index
    @users = User.all
    render Views::Users::Index.new(users: @users)
  end

  # GET /users/1
  def show
    render Views::Users::Show.new(user: @user)
  end

  # GET /users/new
  def new
    @user = User.new
    render Views::Users::New.new(user: @user)
  end

  # GET /users/1/edit
  def edit
    render Views::Users::Edit.new(user: @user)
  end

  # POST /users
  def create
    @user = User.new(user_params)

    if @user.save
      redirect_to @user, notice: "User was successfully created."
    else
      render Views::Users::New.new(user: @user),
             status: :unprocessable_content
    end
  end

  # PATCH/PUT /users/1
  def update
    if @user.update(user_params)
      redirect_to @user, notice: "User was successfully updated.", status: :see_other
    else
      render Views::Users::Edit.new(user: @user),
             status: :unprocessable_content
    end
  end

  # DELETE /users/1
  def destroy
    @user.destroy!
    redirect_to users_url, notice: "User was successfully destroyed.", status: :see_other
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_user
    @user = User.find(params.expect(:id))
  end

  def authorize_user!
    authorize!(@user || User)
  end

  # Only allow a list of trusted parameters through.
  def user_params
    params.expect(user: [:name, :email, { roles: [] }])
  end
end
