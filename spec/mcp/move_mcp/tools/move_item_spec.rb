# frozen_string_literal: true

require "rails_helper"

# #972 — every Items::Move refusal reaches the assistant as readable copy (the
# web UI's items.move.* wording where it exists), never as a raw symbol. The
# action is stubbed so the concurrency-only refusals (:not_found, :box_missing,
# :box_changed) and the unreachable-through-MCP :cross_move are covered too;
# the real same_box / removed paths are exercised in spec/requests/mcp_spec.rb.
RSpec.describe MoveMcp::Tools::MoveItem do
  let(:move) { create(:move) }
  let(:item) { create(:item, move:, box: create(:box, move:, number: 4), name: "Mug") }
  let!(:target) { create(:box, move:, number: 7) }

  def refuse_with(failure)
    action = instance_double(Items::Move, call: Dry::Monads::Result::Failure.new(failure))
    allow(Items::Move).to receive(:new).and_return(action)
    token = create(:move_integration_token, move:, created_by: move.created_by)
    context = { move:, token:, actor: move.created_by }
    described_class.call(item_id: item.id, to_box_number: 7, server_context: context)
  end

  def text(response) = response.content.first[:text]

  {
    same_box: "The item is already in that box.",
    removed: "Restore this item before moving it to another box.",
    cross_move: "That box isn't part of this move.",
    box_missing: "That box isn't part of this move.",
    not_found: "That item no longer exists in this move.",
    box_changed: "The item was moved by someone else at the same time — try again.",
    move_archived: "This move is archived and is read-only."
  }.each do |failure, message|
    it "maps :#{failure} to readable copy" do
      response = refuse_with(failure)

      aggregate_failures do
        expect(response.error?).to be(true)
        expect(text(response)).to eq(message)
      end
    end
  end

  it "names the unpacked destination box and says to reopen it before moving into it" do
    expect(text(refuse_with(:box_unpacked)))
      .to eq("Box #{target.number} is already unpacked — reopen it before moving items into it.")
  end

  it "falls back to generic copy for an unknown failure instead of echoing it" do
    response = refuse_with(:some_new_reason)

    aggregate_failures do
      expect(response.error?).to be(true)
      expect(text(response)).to eq("Could not move the item.")
      expect(text(response)).not_to include("some_new_reason")
    end
  end

  it "falls back to generic copy for validation errors" do
    expect(text(refuse_with(ActiveModel::Errors.new(item)))).to eq("Could not move the item.")
  end
end
