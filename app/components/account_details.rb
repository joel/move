# frozen_string_literal: true

module Components
  class AccountDetails < Components::Base
    def initialize(user:)
      @user = user
    end

    def view_template
      div(class: "ha-card p-8") do
        div(class: "flex items-center gap-6") do
          render_avatar
          div(class: "flex-1") do
            h2(class: "font-headline text-2xl font-bold") do
              plain(@user.name.presence || "Unnamed")
            end
            p(class: "mt-1 text-sm " \
                     "text-[var(--ha-on-surface-variant)]") do
              plain @user.email
            end
            render_role_chip
          end
        end
      end
    end

    private

    def render_avatar
      div(class: "flex h-20 w-20 flex-shrink-0 items-center " \
                 "justify-center rounded-full " \
                 "bg-[var(--ha-primary-container)]/20 " \
                 "text-2xl font-bold " \
                 "text-[var(--ha-primary)]") do
        plain user_initials
      end
    end

    def render_role_chip
      div(class: "mt-3") do
        span(class: "inline-flex rounded-full px-3 py-1 " \
                    "text-[10px] font-bold uppercase tracking-widest " \
                    "bg-[var(--ha-surface-high)] " \
                    "text-[var(--ha-on-surface-variant)]") do
          plain role_label
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
