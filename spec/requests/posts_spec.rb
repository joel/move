# frozen_string_literal: true

require "rails_helper"

RSpec.describe "/posts" do
  let!(:user) { create(:user) }

  let(:valid_attributes) { { title: "A Post", body: "Some body" } }
  let(:invalid_attributes) { { title: "", body: "Some body" } }
  let(:new_attributes) { { title: "Updated title", body: "Updated body" } }

  before { stub_current_user(user) }

  describe "GET /index" do
    it "renders a successful response" do
      create(:post, user: user)
      get posts_url
      expect(response).to be_successful
    end
  end

  describe "GET /show" do
    it "renders a successful response" do
      post = create(:post, user: user)
      get post_url(post)
      expect(response).to be_successful
    end
  end

  describe "GET /new" do
    it "renders a successful response" do
      get new_post_url
      expect(response).to be_successful
    end
  end

  describe "GET /edit" do
    it "renders a successful response" do
      post = create(:post, user: user)
      get edit_post_url(post)
      expect(response).to be_successful
    end
  end

  describe "POST /create" do
    context "with valid parameters" do
      it "creates a new Post owned by the current user" do
        expect do
          post posts_url, params: { post: valid_attributes }
        end.to change(Post, :count).by(1)
        expect(Post.last.user).to eq(user)
      end

      it "redirects to the created post" do
        post posts_url, params: { post: valid_attributes }
        expect(response).to redirect_to(post_url(Post.last))
      end
    end

    context "with invalid parameters" do
      it "does not create a new Post" do
        expect do
          post posts_url, params: { post: invalid_attributes }
        end.not_to change(Post, :count)
      end

      it "renders a response with 422 status (to display the 'new' view)" do
        post posts_url, params: { post: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "PATCH /update" do
    context "with valid parameters" do
      it "updates the requested post" do
        post = create(:post, user: user)
        patch post_url(post), params: { post: new_attributes }
        expect(post.reload.title).to eq("Updated title")
      end

      it "redirects to the post" do
        post = create(:post, user: user)
        patch post_url(post), params: { post: new_attributes }
        expect(response).to redirect_to(post_url(post))
      end
    end

    context "with invalid parameters" do
      it "renders a response with 422 status (to display the 'edit' view)" do
        post = create(:post, user: user)
        patch post_url(post), params: { post: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "DELETE /destroy" do
    it "destroys the requested post" do
      post = create(:post, user: user)
      expect do
        delete post_url(post)
      end.to change(Post, :count).by(-1)
    end

    it "redirects to the posts list" do
      post = create(:post, user: user)
      delete post_url(post)
      expect(response).to redirect_to(posts_url)
    end
  end
end
