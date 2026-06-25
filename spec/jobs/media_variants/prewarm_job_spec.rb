require "rails_helper"

RSpec.describe MediaVariants::PrewarmJob do
  let(:tenant) { Apartment::Tenant.current }

  it "warms the media's display variants" do
    media = create(:media)

    expect { described_class.perform_now(media.id, tenant: tenant) }
      .to change(ActiveStorage::VariantRecord, :count).by(MediaVariants::Prewarm::VARIANTS.size)
  end

  it "restores the tenant before loading the media" do
    media = create(:media)
    allow(Apartment::Tenant).to receive(:switch).and_call_original

    described_class.perform_now(media.id, tenant: tenant)

    expect(Apartment::Tenant).to have_received(:switch).with(tenant)
  end

  it "is safe when the media was since deleted" do
    expect { described_class.perform_now(SecureRandom.uuid, tenant: tenant) }.not_to raise_error
  end
end
