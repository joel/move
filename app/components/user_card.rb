# frozen_string_literal: true

module Components
  class UserCard < Components::Base
    include Phlex::Rails::Helpers::LinkTo
    include Phlex::Rails::Helpers::DOMID

    def initialize(user:)
      @user = user
    end

    def view_template
      div(id: dom_id(@user), class: "ha-card p-6") do
        div(class: "flex items-center gap-4") do
          render_avatar
          div(class: "flex-1 min-w-0") do
            p(class: "font-headline text-lg font-bold truncate") do
              plain @user.name || @user.email
            end
            p(class: "mt-0.5 text-sm truncate " \
                     "text-[var(--ha-on-surface-variant)]") do
              plain @user.email
            end
            render_role_chip
          end
        end
        render_actions unless view_context.action_name == "show"
      end
    end

    private

    def render_avatar
      div(class: "flex h-12 w-12 flex-shrink-0 items-center " \
                 "justify-center rounded-2xl " \
                 "bg-[var(--ha-primary-container)]/20 " \
                 "text-sm font-bold " \
                 "text-[var(--ha-primary)]") do
        plain user_initials
      end
    end

    def render_role_chip
      label = role_label
      div(class: "mt-2") do
        span(class: "inline-flex rounded-full px-2.5 py-0.5 " \
                    "text-[10px] font-bold uppercase tracking-widest " \
                    "bg-[var(--ha-surface-high)] " \
                    "text-[var(--ha-on-surface-variant)]") do
          plain label
        end
      end
    end

    def render_actions
      div(class: "mt-4 flex items-center gap-3") do
        link_to(
          @user,
          class: "text-sm font-semibold text-[var(--ha-primary)] " \
                 "hover:underline"
        ) { "View" }
        if view_context.allowed_to?(:edit?, @user)
          link_to(
            view_context.edit_user_path(@user),
            class: "text-sm font-medium " \
                   "text-[var(--ha-on-surface-variant)] " \
                   "hover:text-[var(--ha-primary)]"
          ) { "Edit" }
        end
      end
    end

    def user_initials
      name = @user.name.presence
      if name
        name.split.pluck(0).first(2).join.upcase
      else
        @user.email.first.upcase
      end
    end

    def role_label
      if @user.role?(:admin) then "Admin"
      elsif @user.role?(:contributor) then "Contributor"
      elsif @user.role?(:viewer) then "Viewer"
      else "No role"
      end
    end
  end
end
