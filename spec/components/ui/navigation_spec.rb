# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Navigation chrome" do # rubocop:disable RSpec/DescribeClass
  let(:labels) { %w[Boxes Search Scan Summary Menu] }

  describe Components::Ui::NavDestinations do
    it "defines the five Design-Spec destinations" do
      expect(described_class.default.map(&:key)).to eq(%i[boxes search scan summary menu])
    end

    it "marks Scan as the elevated centre action" do
      scan = described_class.default.find { |d| d.key == :scan }
      expect(scan.elevated).to be(true)
    end
  end

  describe Components::Ui::BottomTabBar do
    it "renders all five destinations" do
      html = described_class.new(active: :boxes).call
      labels.each { |label| expect(html).to include(label) }
    end

    it "marks the active destination with a sage pill and aria-current" do
      html = described_class.new(active: :search).call
      expect(html).to include('aria-current="page"')
      expect(html).to include("bg-accent-sage")
    end
  end

  describe Components::Ui::Sidebar do
    it "renders all five destinations" do
      html = described_class.new(active: :boxes).call
      labels.each { |label| expect(html).to include(label) }
    end

    it "hides the New Box action with no editable Move in context" do
      # Stateless (no Current.move) → not an editor → no create affordance.
      html = described_class.new(active: :boxes).call
      expect(html).not_to include(I18n.t("ui.buttons.new_box"))
    end

    it "shows the New Box action for an editor on a writable Move" do
      user = create(:user)
      move = create(:move, created_by: user) # creator → admin (editor)
      Current.user = user
      Current.move = move

      html = described_class.new(active: :boxes).call

      expect(html).to include(I18n.t("ui.buttons.new_box"))
    ensure
      Current.reset
    end

    it "is 280px wide and desktop-only" do
      html = described_class.new(active: :boxes).call
      expect(html).to include("w-[280px]")
      expect(html).to include("hidden")
      expect(html).to include("lg:flex")
    end
  end

  describe Components::Ui::AppLayout do
    it "renders sidebar, bottom bar, and yielded content" do
      html = described_class.new(active: :boxes).call { "MAIN_CONTENT" }
      expect(html).to include("MAIN_CONTENT")
      expect(html).to include("w-[280px]")
      expect(html).to include("lg:hidden")
    end
  end
end
