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
  end
end
