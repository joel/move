# frozen_string_literal: true

require "rails_helper"

RSpec.describe Boxes::SuggestDescription do
  let(:move) { create(:move) } # default provider is `fake` (no key)

  def suggest(box) = described_class.new.call(box:)

  it "returns an empty string for a box with no in-box items" do
    box = create(:box, move:)
    expect(suggest(box).value!).to eq("")
  end

  it "ignores removed items" do
    box = create(:box, move:)
    create(:item, move:, box:, name: "Mug", presence_state: "removed")
    expect(suggest(box).value!).to eq("")
  end

  context "with no real provider (fake)" do
    it "joins distinct item categories deterministically, in item order" do
      box = create(:box, move:)
      kitchen = create(:category, move:, name: "Kitchenware")
      books = create(:category, move:, name: "Books")
      create(:item, move:, box:, name: "Mug", category: kitchen)
      create(:item, move:, box:, name: "Plate", category: kitchen)
      create(:item, move:, box:, name: "Novel", category: books)

      expect(suggest(box).value!).to eq("Kitchenware, Books")
    end

    it "falls back to the item label when uncategorised" do
      box = create(:box, move:)
      create(:item, move:, box:, name: "Lamp", category: nil)
      expect(suggest(box).value!).to eq("Lamp")
    end

    it "never calls a vendor provider" do
      box = create(:box, move:)
      create(:item, move:, box:)
      allow(RecognitionProviders).to receive(:for_move)

      suggest(box)

      expect(RecognitionProviders).not_to have_received(:for_move)
    end

    it "emits a deterministic-source event" do
      box = create(:box, move:)
      create(:item, move:, box:)
      allow(Rails.event).to receive(:notify)

      suggest(box)

      expect(Rails.event).to have_received(:notify).with(
        "box.description_suggested", hash_including(box_id: box.id, source: "deterministic")
      )
    end
  end

  context "with a configured real provider" do
    let(:move) { create(:move, recognition_provider: "anthropic", anthropic_api_key: "sk-ant") }
    let(:provider) { instance_double(RecognitionProviders::Anthropic) }

    before { allow(RecognitionProviders).to receive(:for_move).with(move).and_return(provider) }

    it "returns the AI summary and emits an ai-source event" do
      box = create(:box, move:)
      create(:item, move:, box:, name: "Mug")
      allow(provider).to receive(:summarize_contents).and_return("Kitchen things")
      allow(Rails.event).to receive(:notify)

      expect(suggest(box).value!).to eq("Kitchen things")
      expect(Rails.event).to have_received(:notify).with(
        "box.description_suggested", hash_including(source: "ai")
      )
    end

    it "falls back to deterministic (and a fallback event) when the vendor call fails" do
      box = create(:box, move:)
      cat = create(:category, move:, name: "Kitchenware")
      create(:item, move:, box:, name: "Mug", category: cat)
      allow(provider).to receive(:summarize_contents).and_raise(ProviderHttp::Error, "boom")
      allow(Rails.event).to receive(:notify)

      expect(suggest(box).value!).to eq("Kitchenware")
      expect(Rails.event).to have_received(:notify).with(
        "box.description_suggested", hash_including(source: "fallback")
      )
    end

    # Raw Net::HTTP / TLS failures aren't wrapped by ProviderHttp — the broad
    # rescue around the vendor call must still degrade rather than 500.
    it "falls back when the provider raises a raw transport error (TLS / connection reset)" do
      box = create(:box, move:)
      cat = create(:category, move:, name: "Books")
      create(:item, move:, box:, name: "Novel", category: cat)
      allow(provider).to receive(:summarize_contents).and_raise(OpenSSL::SSL::SSLError, "reset")

      expect(suggest(box).value!).to eq("Books")
    end

    it "falls back to deterministic when the AI returns a blank string" do
      box = create(:box, move:)
      cat = create(:category, move:, name: "Books")
      create(:item, move:, box:, name: "Novel", category: cat)
      allow(provider).to receive(:summarize_contents).and_return("  ")

      expect(suggest(box).value!).to eq("Books")
    end

    it "clamps a verbose suggestion to the Box description limit (stays valid)" do
      box = create(:box, move:)
      create(:item, move:, box:, name: "Mug")
      allow(provider).to receive(:summarize_contents).and_return("Stuff, " * 200)

      result = suggest(box).value!

      expect(result.length).to be <= Box::DESCRIPTION_MAX_LENGTH
      expect(box.tap { it.description = result }).to be_valid
    end
  end
end
