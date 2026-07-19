# frozen_string_literal: true

require "rails_helper"

RSpec.describe Components::Ui::InsuranceDossierStatus do
  let(:move) { create(:move) }

  it "carries the stable broadcast-target id" do
    run = create(:insurance_dossier_run, :processing, move:)
    expect(described_class.new(run:).call).to include(%(id="#{described_class::ID}"))
  end

  it "shows the progress bar + count while in progress" do
    run = create(:insurance_dossier_run, :processing, move:, total_count: 10, completed_count: 3)
    html = described_class.new(run:).call
    expect(html).to include(I18n.t("insurance.status.in_progress", done: 3, total: 10))
    expect(html).to include('role="progressbar"')
  end

  # The ready (Download) and failed (Try again) states render route helpers, which
  # need a view context — covered in spec/requests/insurance_dossier_runs_spec.rb.
end
