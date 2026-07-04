# frozen_string_literal: true

# The Activity Feed Wall (G1). Any Move member can read the append-only feed;
# Restore (undelete a discarded record) and Revert (undo the latest edit) are
# editor-only writes that dispatch to the existing domain actions, so they are
# audited and re-versioned like any other change. Thin: load → ActivityFeed read
# model → render, or call the action and redirect.
class ActivitiesController < MoveScopedController
  PAGE = 40

  before_action :require_writable_move!, only: %i[restore revert]

  # GET /moves/:move_id/activity

  #: () -> untyped
  def index
    render activity_index_view(before: cursor)
  end

  # POST /moves/:move_id/activity/:id/restore — re-streams the feed from the top
  # (the restore appends a new audit entry there, and the acted-on row's button
  # drops) + a toast; no reload. HTML clients still redirect.

  #: () -> untyped
  def restore
    result = restore_subject(activities_scope.find(params.expect(:id)))
    stream_feed(result, t(".done"), t(".failed"))
  end

  # POST /moves/:move_id/activity/:id/revert

  #: () -> untyped
  def revert
    result = revert_subject(activities_scope.find(params.expect(:id)))
    stream_feed(result, t(".done"), t(".failed"))
  end

  private

  #: () -> String
  def read_only_redirect_path
    move_activity_path(@move)
  end

  #: () -> untyped
  def activities_scope
    @move.activities
  end

  # Keyset cursor [time, id] for the next (older) page. Both halves come from the
  # last row of the previous page; id disambiguates rows sharing occurred_at
  # (#194). A malformed/partial cursor yields [nil] → the unfiltered first page.

  #: () -> Array[untyped]
  def cursor
    return [nil] if params[:before].blank? || params[:before_id].blank?

    [Time.iso8601(params[:before]), params[:before_id]]
  rescue ArgumentError
    [nil]
  end

  #: () -> Symbol
  def source
    Current.source || :web
  end

  #: (untyped activity) -> untyped
  def restore_subject(activity)
    case activity.subject_type
    when "Box"
      box = @move.boxes.with_discarded.find_by(id: activity.subject_id)
      box && Boxes::Restore.new.call(box:, actor: current_user, source:)
    when "Item"
      item = @move.items.with_discarded.find_by(id: activity.subject_id)
      item && Items::Restore.new.call(item:, actor: current_user, source:)
    end
  end

  #: (untyped activity) -> untyped
  def revert_subject(activity)
    record = revert_target(activity)
    return nil if record.nil? || record.log_version.to_i < 2

    prior = record.at(version: record.log_version - 1)
    apply_revert(activity.subject_type, record, prior)
  end

  #: (untyped activity) -> untyped
  def revert_target(activity)
    case activity.subject_type
    when "Box" then @move.boxes.find_by(id: activity.subject_id)
    when "Item" then @move.items.find_by(id: activity.subject_id)
    end
  end

  #: (untyped type, untyped record, untyped prior) -> untyped
  def apply_revert(type, record, prior)
    case type
    when "Item"
      Items::Update.new.call(item: record, editor: current_user, params: { name: prior.name })
    when "Box"
      Boxes::Update.new.call(box: record, editor: current_user, params: {
                               number: prior.number, length_cm: prior.length_cm, width_cm: prior.width_cm,
                               height_cm: prior.height_cm, weight_kg: prior.weight_kg,
                               description: prior.description
                             })
    end
  end

  # The feed view for the given keyset cursor. `index` passes the request cursor;
  # restore/revert pass the top ([nil]) so the new audit entry is visible.

  #: (?before: Array[untyped]) -> untyped
  def activity_index_view(before: [nil])
    activities = @move.activities.high_signal.recent.before(*before).limit(PAGE).to_a
    feed = ActivityFeed.new(activities, current_user_id: current_user.id, editable: editable_move?)
    last = (activities.last if activities.size == PAGE) #: untyped
    Views::Activities::Index.new(
      move: @move, groups: feed.grouped,
      restorable: feed.restorable_ids, revertable: feed.revertable_ids,
      next_before: last&.occurred_at, next_before_id: last&.id
    )
  end

  # On success re-stream the feed (from the top) + a toast; on failure a toast
  # only. HTML clients still redirect (the fallback).

  #: (untyped result, untyped ok_message, untyped fail_message) -> untyped
  def stream_feed(result, ok_message, fail_message)
    success = result.respond_to?(:success?) && result.success?
    streams = success ? -> { [feed_stream] } : []
    respond_with_streams(streams, redirect: move_activity_path(@move),
                                  toast: true, status: success ? :ok : :unprocessable_content) do
      success ? [:notice, ok_message] : [:alert, fail_message]
    end
  end

  #: () -> untyped
  def feed_stream
    turbo_stream.replace(
      Views::Activities::Index::ID, view_context.render(activity_index_view(before: [nil]))
    )
  end
end
