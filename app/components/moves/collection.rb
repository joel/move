# frozen_string_literal: true

module Components
  module Moves
    # The state-aware Moves-index body (#432). One stable element the sample-Move
    # live reveal replaces over Turbo Streams, so it renders exactly one of:
    #   - provisioning : a "preparing your sample…" placeholder + a subscription to
    #                    the org's demo stream (so the job's broadcast lands here);
    #   - failed       : a fallback card inviting the user to create a Move themselves;
    #   - has moves     : the Move list;
    #   - empty         : the existing empty state.
    # The render-time status check (not a Move query) means a broadcast that lands in
    # the void — job finished before the page subscribed — leaves no stuck spinner:
    # the next load reads "provisioned" and shows the list directly.
    class Collection < Components::Base
      include Phlex::Rails::Helpers::TurboStreamFrom

      ID = "moves-collection"

      # +metrics+ — { move_id => Moves::CardMetrics::Metrics } from the
      # Moves::CardMetrics action (#513), computed by the caller (the controller,
      # or DemoData::Reveal for the broadcast path). REQUIRED, and each card's
      # entry is fetched strictly, so a render site that forgets it fails loudly
      # instead of silently regressing to the old placeholder zeros.

      #: (moves: untyped, organization: untyped, metrics: untyped, ?user: untyped) -> void
      def initialize(moves:, organization:, metrics:, user: nil)
        @moves = moves
        @organization = organization
        @metrics = metrics
        @user = user
      end

      #: () -> void
      def view_template
        div(id: ID, class: "flex flex-col gap-4") do
          if provisioning?
            # Per-user stream: the reveal broadcast carries this user's own
            # membership-scoped Move list, so it must only reach this user — never
            # the whole org subdomain (which would leak other members' Moves once an
            # org has more than its founding owner). The signed name is the boundary.
            turbo_stream_from(@organization, @user, :demo_provisioning)
            preparing_card
          elsif failed?
            failed_card
          elsif @moves.any?
            list
          else
            empty_state
          end
        end
      end

      private

      #: () -> untyped
      def status
        @organization&.demo_data_status
      end

      # Only treat the account as "provisioning"/"failed" while it has no Moves yet —
      # once anything exists the list wins, so a user who created their own Move (or
      # whose sample landed) never sees the onboarding states.

      #: () -> untyped
      def provisioning?
        status == "provisioning" && @moves.none?
      end

      #: () -> untyped
      def failed?
        status == "failed" && @moves.none?
      end

      #: () -> untyped
      def list
        section(class: "flex flex-col gap-4") do
          @moves.each do |move|
            render Components::MoveCard.new(move: move, user: @user, metrics: @metrics.fetch(move.id))
          end
        end
      end

      #: () -> untyped
      def preparing_card
        div(
          class: "flex flex-col gap-4 rounded-card border border-card-border bg-card p-5 " \
                 "animate-pulse opacity-80",
          aria: { live: "polite", busy: "true" }
        ) do
          div(class: "h-5 w-24 rounded-full bg-surface-container-high")
          div(class: "h-6 w-48 rounded bg-surface-container-high")
          p(class: "text-body-md text-on-surface-variant") { I18n.t("moves.sample.preparing") }
          div(class: "h-2 w-full overflow-hidden rounded-full bg-surface-container-high")
        end
      end

      #: () -> untyped
      def failed_card
        render Components::Ui::EmptyState.new(
          title: I18n.t("moves.sample.failed_title"),
          description: I18n.t("moves.sample.failed_body")
        ) do
          render Components::Ui::Button.new(
            label: I18n.t("moves.empty.create"),
            href: new_move_path
          )
        end
      end

      #: () -> untyped
      def empty_state
        render Components::Ui::EmptyState.new(
          title: I18n.t("moves.empty.title"),
          description: I18n.t("moves.empty.description")
        ) do
          render Components::Ui::Button.new(
            label: I18n.t("moves.empty.create"),
            href: new_move_path
          )
        end
      end
    end
  end
end
