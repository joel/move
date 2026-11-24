# frozen_string_literal: true

require "rails_helper"

RSpec.describe Components::Ui::CompactSelect do
  let(:options) { [%w[Admin admin], %w[Viewer viewer]] }

  def render_html(**overrides)
    described_class.new(name: "member[role]", aria_label: "Change role", options:, **overrides).call
  end

  it "renders a label-less select named by its aria-label" do
    html = render_html
    expect(html).to include(%(<select name="member[role]" aria-label="Change role"))
    expect(html).not_to include("<label")
  end

  it "marks the selected option, comparing by string" do
    html = described_class.new(name: "id", aria_label: "Jump", options: [["Box 1", 1], ["Box 2", 2]],
                               selected: "2").call
    expect(html).to include(%(<option value="2" selected>Box 2</option>))
    expect(html).to include(%(<option value="1">Box 1</option>))
  end

  it "wires the auto-submit action only when asked" do
    expect(render_html(auto_submit: true)).to include(%(data-action="change->auto-submit#submit"))
    expect(render_html).not_to include("auto-submit")
  end

  it "renders the rotated chevron overlay" do
    expect(render_html).to include("pointer-events-none").and include("rotate-90")
  end

  it "requires an aria_label" do
    expect { described_class.new(name: "x", options:) }.to raise_error(ArgumentError, /aria_label/)
  end
end
