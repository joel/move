require "rails_helper"

RSpec.describe Move do
  describe "validations" do
    it "is valid with a name, status, unit system and creator" do
      expect(build(:move)).to be_valid
    end

    it "requires a name" do
      expect(build(:move, name: nil)).not_to be_valid
    end

    it "rejects unknown statuses" do
      expect(build(:move, status: "lost")).not_to be_valid
    end

    it "rejects unknown unit systems" do
      expect(build(:move, unit_system: "furlongs")).not_to be_valid
    end

    it "defaults the recognition provider to fake" do
      expect(create(:move).recognition_provider).to eq("fake")
    end

    it "rejects unknown recognition providers" do
      expect(build(:move, recognition_provider: "skynet")).not_to be_valid
    end

    it "defaults the embedding provider to fake" do
      expect(create(:move).embedding_provider).to eq("fake")
    end

    it "rejects unknown embedding providers (#232)" do
      expect(build(:move, embedding_provider: "word2vec")).not_to be_valid
    end

    it "defaults labels_per_box to 2 (Phase 45)" do
      expect(create(:move).labels_per_box).to eq(2)
    end

    it "accepts labels_per_box across the 1..10 range" do
      expect(build(:move, labels_per_box: 1)).to be_valid
      expect(build(:move, labels_per_box: 10)).to be_valid
    end

    it "rejects an out-of-range or non-integer labels_per_box" do
      expect(build(:move, labels_per_box: 0)).not_to be_valid
      expect(build(:move, labels_per_box: 11)).not_to be_valid
      expect(build(:move, labels_per_box: 2.5)).not_to be_valid
    end
  end

  describe "#embedding_provider_ready? (#232/#237)" do
    it "is false for fake" do
      expect(build(:move, embedding_provider: "fake")).not_to be_embedding_provider_ready
    end

    it "is true only when the selected real provider has the Move's own key" do
      expect(build(:move, embedding_provider: "openai", openai_api_key: nil)).not_to be_embedding_provider_ready
      expect(build(:move, embedding_provider: "openai", openai_api_key: "sk")).to be_embedding_provider_ready
      expect(build(:move, embedding_provider: "gemini", gemini_api_key: "gk")).to be_embedding_provider_ready
      expect(build(:move, embedding_provider: "voyage", voyage_api_key: nil)).not_to be_embedding_provider_ready
      expect(build(:move, embedding_provider: "voyage", voyage_api_key: "vk")).to be_embedding_provider_ready
    end
  end

  describe "#embedding_api_key_for (#237)" do
    it "maps each real provider to its key column (openai/gemini reuse the recognition key; voyage is its own)" do
      move = build(:move, openai_api_key: "sk", gemini_api_key: "gk", voyage_api_key: "vk")

      expect(move.embedding_api_key_for("openai")).to eq("sk")
      expect(move.embedding_api_key_for("gemini")).to eq("gk")
      expect(move.embedding_api_key_for("voyage")).to eq("vk")
    end

    it "is nil for fake/unknown providers (they need no key)" do
      expect(build(:move).embedding_api_key_for("fake")).to be_nil
      expect(build(:move).embedding_api_key_for("anthropic")).to be_nil
    end
  end

  describe "#image_generation_ready? (#416)" do
    it "is true for fake (network-free placeholder, no key)" do
      expect(build(:move, image_provider: "fake")).to be_image_generation_ready
    end

    it "is true for openai only when the Move has its own key (strict BYO)" do
      expect(build(:move, image_provider: "openai", openai_api_key: nil)).not_to be_image_generation_ready
      expect(build(:move, image_provider: "openai", openai_api_key: "sk")).to be_image_generation_ready
    end
  end

  describe "#image_api_key_for + #provider_powers (#416)" do
    it "reuses the openai key column and badges openai with :image" do
      move = build(:move, openai_api_key: "sk")

      expect(move.image_api_key_for("openai")).to eq("sk")
      expect(move.image_api_key_for("fake")).to be_nil
      expect(move.provider_powers("openai")).to include(:image)
    end
  end

  describe "#writable?" do
    it "is writable unless archived" do
      expect(build(:move, status: "planned")).to be_writable
      expect(build(:move, :archived)).not_to be_writable
    end
  end

  describe "recognition provider keys" do
    it "encrypts the provider API keys at rest (ciphertext in the column)" do
      move = create(:move, openai_api_key: "sk-secret")

      stored = described_class.connection.select_value(
        described_class.sanitize_sql(["SELECT openai_api_key FROM moves WHERE id = ?", move.id])
      )
      expect(stored).not_to include("sk-secret")
      expect(move.reload.openai_api_key).to eq("sk-secret")
    end

    it "returns the matching key via #recognition_api_key_for (nil for fake/unknown)" do
      move = build(:move, gemini_api_key: "g-key")
      expect(move.recognition_api_key_for("gemini")).to eq("g-key")
      expect(move.recognition_api_key_for("fake")).to be_nil
      expect(move.recognition_api_key_for("openai")).to be_nil
    end

    describe "#recognition_ready?" do
      it "is always ready for fake" do
        expect(build(:move, recognition_provider: "fake")).to be_recognition_ready
      end

      it "needs the matching key for a real provider" do
        expect(build(:move, recognition_provider: "openai", openai_api_key: nil)).not_to be_recognition_ready
        expect(build(:move, recognition_provider: "openai", openai_api_key: "sk")).to be_recognition_ready
      end
    end

    describe "#recognition_model_for (#187)" do
      it "returns the stored override for a real provider, nil for blank/fake/unknown" do
        move = build(:move, anthropic_model: "claude-opus-4-8")
        expect(move.recognition_model_for("anthropic")).to eq("claude-opus-4-8")
        expect(move.recognition_model_for("openai")).to be_nil
        expect(move.recognition_model_for("fake")).to be_nil
        expect(move.recognition_model_for("nope")).to be_nil
      end
    end
  end
end
