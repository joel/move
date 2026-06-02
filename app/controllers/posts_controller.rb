# frozen_string_literal: true

# Source: https://github.com/rails/rails/blob/7-1-stable/railties/lib/rails/generators/rails/scaffold_controller/templates/controller.rb.tt
class PostsController < ApplicationController
  before_action :set_post, only: %i[show edit update destroy]
  before_action :require_authenticated_user!, only: %i[new create edit update destroy]
  before_action :authorize_post!, only: %i[edit update destroy]

  # GET /posts
  def index
    @posts = Post.includes(:user).all
    render Views::Posts::Index.new(posts: @posts)
  end

  # GET /posts/1
  def show
    render Views::Posts::Show.new(post: @post)
  end

  # GET /posts/new
  def new
    @post = current_user.posts.new(title: "A Post", body: "...")
    render Views::Posts::New.new(post: @post)
  end

  # GET /posts/1/edit
  def edit
    render Views::Posts::Edit.new(post: @post)
  end

  # POST /posts
  def create
    @post = current_user.posts.new(post_params)

    if @post.save
      redirect_to @post, notice: "Post was successfully created."
    else
      render Views::Posts::New.new(post: @post), status: :unprocessable_content
    end
  end

  # PATCH/PUT /posts/1
  def update
    if @post.update(post_params)
      redirect_to @post, notice: "Post was successfully updated.", status: :see_other
    else
      render Views::Posts::Edit.new(post: @post), status: :unprocessable_content
    end
  end

  # DELETE /posts/1
  def destroy
    @post.destroy!
    redirect_to posts_url, notice: "Post was successfully destroyed.", status: :see_other
  end

  private

  def set_post
    @post = Post.find(params.expect(:id))
  end

  def authorize_post!
    authorize! @post, to: :"#{action_name}?"
  end

  # Only allow a list of trusted parameters through.
  def post_params
    params.expect(post: %i[title body])
  end
end
