# frozen_string_literal: true

# Read model for the Activity Feed page. Batch-loads the actors (public.users)
# and the (possibly discarded) subjects for a page of Activity rows, groups them
# by day, and decides which rows offer Restore (a still-discarded deleted record)
# or Revert (the latest edit of a record that has prior versions). Keeps
# ActivitiesController thin — it just renders what this exposes.
#
# NOTE — the group_by / select / max_by below run in Ruby ON PURPOSE; they are
# NOT the "push aggregation to the database" anti-pattern (AGENTS.md §1 #5). The
# controller hands us one **bounded, keyset-paginated page** of Activity rows
# (`@move.activities.<scopes>.limit(PAGE).to_a`) that is rendered in full, so every
# operation here works on records **already in memory because they're displayed**,
# not on rows loaded just to compute a number:
#   - `grouped`        — day-buckets the page's presenters for the feed's date
#                        headers (you can't group-in-SQL what you're rendering).
#   - `load_subjects`  — groups the page by subject_type to BATCH-LOAD related
#                        records in one query per type (this *is* N+1 avoidance;
#                        SQL-ifying it would dismantle the batch loader).
#   - `latest_updates` — picks the latest edit per subject for the Revert flag,
#                        over rows we already hold; a SQL window query would be a
#                        redundant second fetch of the on-screen page.
# Re-deriving any of these in SQL would add a redundant query (or is impossible),
# i.e. a regression — not a cleanup. The rule targets O(N) row-loads-to-aggregate
# (e.g. the volume summary, #285), which is a different shape from this.
class ActivityFeed
  UPDATE_ACTIONS = %w[item.updated box.updated].freeze
  DELETE_ACTIONS = %w[box.deleted item.deleted].freeze

  def initialize(activities, current_user_id:, editable:)
    @activities = activities
    @current_user_id = current_user_id
    @editable = editable
    @actors = load_actors
    @subjects = load_subjects
  end

  # [[Date, [ActivityPresenter, ...]], ...] newest day first (input is pre-sorted).
  def grouped
    presenters.group_by { |p| p.occurred_at.to_date }
              .sort_by { |date, _| date }.reverse
  end

  # activity ids whose deleted subject is still discarded and so can be restored.
  def restorable_ids
    return Set.new unless @editable

    @activities.select { |a| restorable?(a) }.to_set(&:id)
  end

  # activity ids for the latest edit of each subject that has a prior version.
  def revertable_ids
    return Set.new unless @editable

    latest_updates.select { |a| revertable?(a) }.to_set(&:id)
  end

  private

  def presenters
    @presenters ||= @activities.map do |activity|
      ActivityPresenter.new(activity, actors: @actors, subjects: @subjects,
                                      current_user_id: @current_user_id)
    end
  end

  def load_actors
    ids = @activities.filter_map(&:actor_id).uniq
    ids.any? ? User.where(id: ids).index_by(&:id) : {}
  end

  # Boxes/Items resolve with_discarded (a deleted subject must still be nameable);
  # the rest are never discardable. Target boxes (item.moved) are loaded too.
  def load_subjects
    by_type = @activities.group_by(&:subject_type)
    map = {}
    load_into(map, "Box", Box.with_discarded, box_ids(by_type))
    load_into(map, "Item", Item.with_discarded, ids_for(by_type, "Item"))
    { "Move" => Move, "Media" => Media, "Category" => Category, "Tag" => Tag, "Room" => Room }
      .each { |type, klass| load_into(map, type, klass, ids_for(by_type, type)) }
    map
  end

  def load_into(map, type, relation, ids)
    return if ids.blank?

    relation.where(id: ids).find_each { |record| map[[type, record.id]] = record }
  end

  def ids_for(by_type, type)
    (by_type[type] || []).map(&:subject_id)
  end

  def box_ids(by_type)
    ids_for(by_type, "Box") + @activities.filter_map { |a| a.metadata["to_box_id"] }
  end

  def restorable?(activity)
    return false unless DELETE_ACTIONS.include?(activity.action)

    @subjects[[activity.subject_type, activity.subject_id]]&.try(:discarded?)
  end

  def latest_updates
    @activities.select { |a| UPDATE_ACTIONS.include?(a.action) }
               .group_by { |a| [a.subject_type, a.subject_id] }
               .values.map { |group| group.max_by(&:occurred_at) }
  end

  def revertable?(activity)
    record = @subjects[[activity.subject_type, activity.subject_id]]
    return false if record.nil? || record.try(:discarded?)

    record.respond_to?(:log_version) && record.log_version.to_i > 1
  end
end
