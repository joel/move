require "rails_helper"

RSpec.describe MoveIntegrationToken do
  describe "validations" do
    it "is valid with the factory defaults" do
      expect(build(:move_integration_token)).to be_valid
    end

    it "requires a name" do
      expect(build(:move_integration_token, name: "")).not_to be_valid
    end

    it "requires a token digest" do
      expect(build(:move_integration_token, token_digest: nil)).not_to be_valid
    end

    it "forbids two tokens sharing a digest" do
      digest = described_class.digest(described_class.generate_raw_token)
      create(:move_integration_token, token_digest: digest)

      expect(build(:move_integration_token, token_digest: digest)).not_to be_valid
    end
  end

  describe ".generate_raw_token" do
    it "prefixes the token so it is recognisable" do
      expect(described_class.generate_raw_token).to start_with("mcp_")
    end

    it "mints a fresh value each call" do
      expect(described_class.generate_raw_token)
        .not_to eq(described_class.generate_raw_token)
    end
  end

  describe ".digest" do
    it "is stable for the same raw token" do
      raw = described_class.generate_raw_token
      first = described_class.digest(raw)
      expect(described_class.digest(raw)).to eq(first)
    end

    it "never stores the raw token" do
      raw = described_class.generate_raw_token
      expect(described_class.digest(raw)).not_to include(raw)
    end
  end

  describe ".authenticate" do
    let(:raw) { described_class.generate_raw_token }
    let!(:token) { create(:move_integration_token, token_digest: described_class.digest(raw)) }

    it "resolves an active token from its raw value" do
      expect(described_class.authenticate(raw)).to eq(token)
    end

    it "rejects a revoked token" do
      token.update!(revoked_at: Time.current)
      expect(described_class.authenticate(raw)).to be_nil
    end

    it "rejects an unknown token" do
      expect(described_class.authenticate("mcp_nope")).to be_nil
    end

    it "rejects a blank token" do
      expect(described_class.authenticate("")).to be_nil
      expect(described_class.authenticate(nil)).to be_nil
    end
  end

  describe "#revoked?" do
    it "reflects revoked_at" do
      expect(build(:move_integration_token)).not_to be_revoked
      expect(build(:move_integration_token, :revoked)).to be_revoked
    end
  end

  describe "#touch_last_used!" do
    it "records the time without running validations" do
      token = create(:move_integration_token)
      freeze_time do
        token.touch_last_used!
        expect(token.reload.last_used_at).to eq(Time.current)
      end
    end
  end
end
