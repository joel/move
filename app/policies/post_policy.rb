# frozen_string_literal: true

class PostPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def new?
    create?
  end

  def create?
    user.present?
  end

  def edit?
    admin? || owner?
  end

  def update?
    edit?
  end

  def destroy?
    edit?
  end

  private

  def owner?
    user && record.user_id == user.id
  end
end
