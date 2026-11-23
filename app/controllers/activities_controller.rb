# frozen_string_literal: true

# The Activity Feed Wall (G1). Any Move member can read the append-only feed;
# Restore (undelete a discarded record) and Revert (undo the latest edit) are
# editor-only writes that dispatch to the existing domain actions, so they are
# audited and re-versioned like any other change. Thin: load → ActivityFeed read
# model → render, or call the action and redirect.
class ActivitiesController < MoveScopedController
  PAGE = 40
  # The largest uuid: a keyset cursor half that sorts after every real id.
  MAX_UUID = "ffffffff-ffff-ffff-ffff-ffffffffffff"
  # Restore refusals a user can act on get their own toast (#894, #901);
  # anything else is the generic "couldn't restore".
  RESTORE_FAILURES = %i[parent_discarded stale not_found].freeze
  # Refusals because the entry the user clicked is out of date: its Restore
  # button is removed in place (the page, scroll and focus stay put).
  OUTDATED_ENTRY_FAILURES = %i[stale not_found].freeze

  before_action :require_writable_move!, only: %i[restore revert]

  # GET /moves/:move_id/activity

  #: () -> untyped
  def index
    render activity_index_view(before: cursor)
  end

  # POST /moves/:move_id/activity/:id/restore — re-streams the feed from the top
  # (the restore appends a new audit entry there, and the acted-on row's button
  # drops) + a toast; no reload. HTML clients still redirect. An item whose box
  # is still deleted is refused (#894) with "restore the box first", linking to
  # the box's own restore entry when the feed has one. A record restored (and
  # maybe deleted again) by someone else meanwhile is refused (#901) with a
  # toast saying so, and that entry's Restore button is removed. An entry whose
  # deletion was superseded (restored and deleted again) is refused the same way.

  #: () -> untyped
  def restore
    activity = activities_scope.find(params.expect(:id))
    result = restore_subject(activity)
    link_box_restore_entry(activity) if result in Dry::Monads::Failure(:parent_discarded)
    outdated = OUTDATED_ENTRY_FAILURES.include?(failure_reason(result))
    stream_feed(result, t(".done"), restore_failure_message(result),
                failure_streams: outdated ? [turbo_stream.remove(Views::Activities::Index.restore_id(activity.id))] : [])
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
      box && current_entry(activity, box) { Boxes::Restore.new.call(box:, actor: current_user, source:) }
    when "Item"
      item = @move.items.with_discarded.find_by(id: activity.subject_id)
      item && current_entry(activity, item) { Items::Restore.new.call(item:, actor: current_user, source:) }
    when "Media"
      media = @move.media.with_discarded.find_by(id: activity.subject_id)
      media && current_entry(activity, media) { Photos::Restore.new.call(media:, actor: current_user, source:) }
    end
  end

  # An entry undoes the deletion it records — its batch (ActivityFeed hides the
  # button on a superseded one). A record restored and deleted again since
  # carries a newer batch: refuse rather than undo that newer deletion from the
  # old entry (#901). The restore then re-checks the batch under its row lock.

  #: (untyped activity, untyped record) { () -> untyped } -> untyped
  def current_entry(activity, record)
    batch_id = activity.metadata["discard_batch_id"]
    return Dry::Monads::Result::Failure.new(:stale) if batch_id && record.discarded? && record.discard_batch_id != batch_id

    yield
  end

  #: (untyped result) -> String
  def restore_failure_message(result)
    reason = failure_reason(result)
    RESTORE_FAILURES.include?(reason) ? t(".#{reason}") : t(".failed")
  end

  #: (untyped result) -> untyped
  def failure_reason(result)
    result.failure if result.respond_to?(:failure?) && result.failure?
  end

  # Points the failure toast at the deleted box's `box.deleted` row. The feed
  # is keyset-paginated, so the link opens the page that STARTS at that row:
  # the cursor is strictly-older-than (occurred_at, id), and the max uuid as
  # the id half keeps every row at that instant — the entry itself included.
  # The link rides flash.now for the stream render, the persistent flash for
  # the no-JS redirect (the respond_with_box_toast pattern).

  #: (untyped activity) -> untyped
  def link_box_restore_entry(activity)
    entry = box_restore_entry(activity) or return
    link_flash = request.format.turbo_stream? ? flash.now : flash
    link_flash[:action_href] = move_activity_path(
      @move, before: entry.occurred_at.iso8601(6), before_id: MAX_UUID
    )
    link_flash[:action_label] = t("activities.restore.view_box_entry")
  end

  #: (untyped activity) -> untyped
  def box_restore_entry(activity)
    box_id = parent_box_id(activity)
    return if box_id.nil?

    activities_scope.high_signal.where(subject_type: "Box", subject_id: box_id, action: "box.deleted")
                    .recent.first
  end

  #: (untyped activity) -> untyped
  def parent_box_id(activity)
    parents = activity.subject_type == "Media" ? @move.media : @move.items
    parents.with_discarded.where(id: activity.subject_id).pick(:box_id)
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
  # plus any `failure_streams`. HTML clients still redirect (the fallback).

  #: (untyped result, untyped ok_message, untyped fail_message, ?failure_streams: Array[untyped]) -> untyped
  def stream_feed(result, ok_message, fail_message, failure_streams: [])
    success = result.respond_to?(:success?) && result.success?
    streams = success ? -> { [feed_stream] } : failure_streams
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
