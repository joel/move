# frozen_string_literal: true

require "rails_helper"

# The activity log is populated by subscribing to the domain event stream. These
# exercise the live wiring (initializer → subscriber → Builder → row) by emitting
# real Rails.event events, the same way the domain actions do.
RSpec.describe Activity::RecordSubscriber do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:box) { create(:box, move:) }

  def emit(name, **payload)
    Rails.event.notify(name, **payload)
  end

  it "records a mapped event with its subject, actor and Move" do
    expect { emit("box.updated", box_id: box.id, move_id: move.id, editor_id: actor.id) }
      .to change(Activity, :count).by(1)

    expect(Activity.last).to have_attributes(
      action: "box.updated", subject_type: "Box", subject_id: box.id,
      actor_id: actor.id, move_id: move.id, low_signal: false
    )
  end

  it "skips events it does not map" do
    expect { emit("recognition_run.processing", recognition_run_id: SecureRandom.uuid) }
      .not_to change(Activity, :count)
    expect { emit("mcp.tool_called", source: :mcp, tool: "x", move_id: move.id) }
      .not_to change(Activity, :count)
  end

  it "skips a mapped event with no Move in the payload" do
    expect { emit("box.updated", box_id: box.id, editor_id: actor.id) }
      .not_to change(Activity, :count)
  end

  it "flags low-signal reads so the default feed can hide them" do
    emit("manifest.viewed", box_id: box.id, move_id: move.id, actor_id: actor.id)
    expect(Activity.last).to be_low_signal
  end

  it "resolves a vocabulary subject from its kind" do
    category = create(:category, move:)
    emit("vocabulary.created", kind: "category", record_id: category.id, move_id: move.id, actor_id: actor.id)

    expect(Activity.last).to have_attributes(subject_type: "Category", subject_id: category.id)
  end

  it "normalises the actor from whichever key the payload used" do
    emit("item.moved", item_id: create(:item, move:, box:).id, move_id: move.id,
                       to_box_id: box.id, mover_id: actor.id)
    expect(Activity.last.actor_id).to eq(actor.id)
    expect(Activity.last.metadata["to_box_id"]).to eq(box.id)
  end

  it "falls back to Current.source when the payload omits it" do
    Current.source = :system
    emit("move.created", move_id: move.id)
    expect(Activity.last.source).to eq("system")
  ensure
    Current.source = nil
  end

  it "is append-only (records are read-only once persisted)" do
    emit("box.created", box_id: box.id, move_id: move.id, created_by_id: actor.id)
    expect { Activity.last.update!(action: "tampered") }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
