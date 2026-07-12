# frozen_string_literal: true

module Components
  module Members
    # F1/D14 — one pending invitation (#608): email, role chip, expiry, Resend
    # and Revoke. Stable per-invitation id so the controller can replace the row
    # in place on resend (fresh expiry) and remove it on revoke. An expired but
    # unaccepted row stays visible with an "Expired" tint — Resend revives it
    # (the partial unique index means it blocks a fresh invite until then).
    class PendingRow < Components::Base
      include Phlex::Rails::Helpers::ButtonTo

      # @rbs skip
      def self.dom_id(invitation)
        "pending-invitation-#{invitation.id}"
      end

      #: (move: untyped, invitation: untyped, ?highlight: untyped) -> void
      def initialize(move:, invitation:, highlight: false)
        @move = move
        @invitation = invitation
        @highlight = highlight
      end

      #: () -> void
      def view_template
        div(
          id: self.class.dom_id(@invitation), data: row_data,
          class: "flex flex-col gap-3 rounded-card border border-card-border bg-card p-4 " \
                 "transition sm:flex-row sm:items-center sm:justify-between"
        ) do
          identity
          actions
        end
      end

      private

      #: () -> untyped
      def row_data
        @highlight ? { controller: "highlight" } : {}
      end

      #: () -> untyped
      def identity
        div(class: "flex flex-1 flex-col gap-1") do
          span(class: "text-body-lg text-text-warm") { @invitation.email }
          div(class: "flex items-center gap-2") do
            render Components::Ui::Chip.new(label: I18n.t("members.roles.#{@invitation.role}"))
            span(class: "text-label-caps uppercase #{expiry_tint}") { expiry_label }
          end
        end
      end

      #: () -> String
      def expiry_tint
        @invitation.expired? ? "text-error" : "text-muted"
      end

      #: () -> String
      def expiry_label
        if @invitation.expired?
          I18n.t("members.pending.expired")
        else
          I18n.t("members.pending.expires_in",
                 time: helpers.distance_of_time_in_words(Time.current, @invitation.expires_at))
        end
      end

      #: () -> untyped
      def actions
        div(class: "flex shrink-0 items-center gap-2") do
          button_to(
            I18n.t("members.pending.resend"),
            resend_move_invitation_path(@move, @invitation),
            method: :post, class: "ha-button", form_class: "shrink-0"
          )
          button_to(
            I18n.t("members.pending.revoke"),
            move_invitation_path(@move, @invitation),
            method: :delete, class: "ha-button text-error", form_class: "shrink-0",
            data: { turbo_confirm: I18n.t("members.pending.revoke_confirm", email: @invitation.email) }
          )
        end
      end
    end
  end
end
