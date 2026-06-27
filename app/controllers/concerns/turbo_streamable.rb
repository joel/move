# frozen_string_literal: true

# Shared helper for responding to a same-page mutation with targeted Turbo
# Stream DOM updates (no full-page reload) while keeping a redirect fallback for
# non-Turbo clients. Formalises the pattern already established ad-hoc in
# ItemsController#update and SettingsController#respond_ai_update so every
# controller in the no-reload program responds the same way.
#
#   # Rapid-tap action — surgical DOM updates, no toast (would spam):
#   respond_with_streams(streams, redirect: move_box_unpacking_path(@move, @box))
#
#   # Action that warrants a confirmation toast:
#   respond_with_streams(streams, redirect: move_vocabularies_path(@move), toast: true) do
#     result.success? ? [:notice, t(".created")] : [:alert, t(".failed")]
#   end
#
# On a Turbo Stream request it renders `streams` (an Array of turbo_stream
# actions, each typically a `turbo_stream.replace/remove/append`). When `toast:`
# is set and the block yields a `[flash_key, message]` pair, it sets `flash.now`
# and appends a FlashToasts replacement so the toast surfaces without a redirect
# (the FlashToasts container is always present in the layout).
#
# On an HTML request it redirects to `redirect`, carrying the flash when the
# block yielded one. Turbo also follows this 3xx, so a `before_action` guard that
# redirects (e.g. require_writable_move!) keeps working unchanged — it simply
# never reaches here.
module TurboStreamable
  extend ActiveSupport::Concern

  private

  # `streams` is an Array of turbo_stream actions, OR a callable returning one —
  # pass a lambda when building the streams is expensive (e.g. rendering a whole
  # detail view) so the work only happens on the Turbo path, never on the HTML
  # redirect branch.
  def respond_with_streams(streams, redirect:, toast: false, status: :ok)
    flash_key, message = block_given? ? yield : nil

    respond_to do |format|
      format.turbo_stream do
        actions = streams.respond_to?(:call) ? Array(streams.call) : streams
        if toast && flash_key
          flash.now[flash_key] = message
          actions += [turbo_stream.replace(Components::FlashToasts::ID, Components::FlashToasts.new)]
        end
        render turbo_stream: actions, status: status
      end
      format.html do
        flash_key ? redirect_to(redirect, flash: { flash_key => message }) : redirect_to(redirect)
      end
    end
  end
end
