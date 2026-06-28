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

  it "records a recognition provider change, keeping the provider in metadata" do
    expect { emit("move.recognition_provider_changed", move_id: move.id, actor_id: actor.id, provider: "openai") }
      .to change(Activity, :count).by(1)

    expect(Activity.last).to have_attributes(
      action: "move.recognition_provider_changed", subject_type: "Move", subject_id: move.id, actor_id: actor.id
    )
    expect(Activity.last.metadata).to include("provider" => "openai")
  end

  it "records a recognition model change, keeping the provider and model in metadata (#187)" do
    expect do
      emit("move.recognition_model_changed", move_id: move.id, actor_id: actor.id, provider: "openai", model: "gpt-5")
    end.to change(Activity, :count).by(1)

    expect(Activity.last.action).to eq("move.recognition_model_changed")
    expect(Activity.last.metadata).to include("provider" => "openai", "model" => "gpt-5")
  end

  it "records an AI Capability key being set, keeping the provider in metadata (#242)" do
    expect { emit("move.provider_key_set", move_id: move.id, actor_id: actor.id, provider: "voyage") }
      .to change(Activity, :count).by(1)
    expect(Activity.last.action).to eq("move.provider_key_set")
    expect(Activity.last.metadata).to include("provider" => "voyage")
  end

  it "records an AI Capability key removal (#242)" do
    expect { emit("move.provider_key_removed", move_id: move.id, actor_id: actor.id, provider: "gemini") }
      .to change(Activity, :count).by(1)
    expect(Activity.last.action).to eq("move.provider_key_removed")
  end

  it "records a labels-per-box change, keeping the count in metadata (#310)" do
    expect { emit("move.labels_per_box_changed", move_id: move.id, actor_id: actor.id, labels_per_box: 5) }
      .to change(Activity, :count).by(1)
    expect(Activity.last.action).to eq("move.labels_per_box_changed")
    expect(Activity.last.metadata).to include("labels_per_box" => 5)
  end

  it "records a photo move, keeping the target box in metadata (#317)" do
    photo = create(:media, move:, box:)
    target = create(:box, move:)
    expect { emit("media.moved", media_id: photo.id, move_id: move.id, to_box_id: target.id, actor_id: actor.id) }
      .to change(Activity, :count).by(1)
    expect(Activity.last).to have_attributes(action: "media.moved", subject_type: "Media", subject_id: photo.id)
    expect(Activity.last.metadata).to include("to_box_id" => target.id)
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
    room = create(:room, move:)
    emit("vocabulary.created", kind: "room", record_id: room.id, move_id: move.id, actor_id: actor.id)

    expect(Activity.last).to have_attributes(subject_type: "Room", subject_id: room.id)
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
