# frozen_string_literal: true

# Renders one Activity row's human summary from structured data + i18n (the log
# stores no English). The actor and the (possibly discarded) subject are resolved
# in batch by the controller and passed in, so a "deleted Box 7" row can still
# name the box. Deletion/restore rows carry the terracotta accent (the design's
# "destructive" tone); everything else is neutral.
class ActivityPresenter
  ACCENT_ACTIONS = %w[box.deleted item.deleted box.restored item.undeleted
                      media.discarded media.undiscarded vocabulary.removed].freeze

  def initialize(activity, actors:, subjects:, current_user_id:)
    @activity = activity
    @actors = actors
    @subjects = subjects
    @current_user_id = current_user_id
  end

  attr_reader :activity

  # The actor's display name — "You" for the viewer, the user's name, or a label
  # derived from the source (assistant/system) when there is no user.
  def actor_label
    return I18n.t("activities.actor.you") if actor && actor.id == @current_user_id
    return actor_user.name.presence || I18n.t("activities.actor.someone") if actor_user
    return I18n.t("activities.actor.assistant") if activity.mcp?
    return I18n.t("activities.actor.system") if activity.system?

    I18n.t("activities.actor.someone")
  end

  # Translated predicate, e.g. "moved Lamp to Box 4". Falls back to the raw action
  # name if a summary key is somehow missing (never user-facing in practice).
  def predicate
    I18n.t("activities.summary.#{activity.action}", **interpolations, default: activity.action)
  end

  def accent?
    ACCENT_ACTIONS.include?(activity.action)
  end

  def source_label
    I18n.t("activities.source.#{activity.source}")
  end

  delegate :occurred_at, to: :activity

  # Two-letter avatar initials from the actor's name (falls back to the label).
  def initials
    basis = actor_user&.name.presence || actor_label
    basis.scan(/[[:alnum:]]+/).first(2).pluck(0).join.upcase.presence || "?"
  end

  private

  def actor
    actor_user
  end

  def actor_user
    @actors[activity.actor_id]
  end

  def interpolations
    {
      subject: subject_label, target: target_label,
      role: activity.metadata["role"], unit_system: activity.metadata["unit_system"],
      token_name: activity.metadata["token_name"], kind: kind_label,
      provider: activity.metadata["provider"], model: activity.metadata["model"],
      labels_per_box: activity.metadata["labels_per_box"]
    }
  end

  # Action-aware: the grammatical subject of the summary depends on the event,
  # not just the polymorphic subject_type (membership rows say "a member", not
  # the Move they hang off).
  def subject_label
    case activity.action
    when /\Amove_membership\./ then I18n.t("activities.subject.member")
    when /\Amove\./ then I18n.t("activities.subject.move")
    when /\Avocabulary\./, /\A(box|item|room)\b/
      named_subject_label
    when /\Amedia\./ then I18n.t("activities.subject.photo")
    else I18n.t("activities.subject.unknown")
    end
  end

  def named_subject_label
    record = subject
    return I18n.t("activities.subject.unknown") if record.nil?
    return I18n.t("activities.subject.box", number: record.number) if record.is_a?(Box)

    record.try(:name).presence || I18n.t("activities.subject.unknown")
  end

  def subject
    @subjects[[activity.subject_type, activity.subject_id]]
  end

  def target_label
    box = @subjects[["Box", activity.metadata["to_box_id"]]]
    box && I18n.t("activities.subject.box", number: box.number)
  end

  def kind_label
    kind = activity.metadata["kind"]
    kind && I18n.t("activities.kind.#{kind}", default: kind)
  end
end
