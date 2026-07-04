# frozen_string_literal: true

# Dev-only living reference for the Move design system (Phase D0). Renders every
# primitive in every state, light + dark. Available in local environments or to
# admins in production; hidden (404) otherwise.
class StyleGuideController < ApplicationController
  #: () -> untyped
  def show
    return head :not_found unless viewable?

    render Views::StyleGuide::Show.new
  end

  private

  #: () -> untyped
  def viewable?
    Rails.env.local? || current_user&.role?(:admin)
  end
end
