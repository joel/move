# frozen_string_literal: true

require "rails_helper"

RSpec.describe Components::Ui::IconButton do
  def render_html(**args)
    described_class.new(**args).call { "icon" }
  end

  it "renders an anchor when given an href" do
    html = render_html(href: "/boxes/2", label: "Next box")
    expect(html).to start_with(%(<a href="/boxes/2" aria-label="Next box" class="rounded-full p-2))
    expect(html).to include("icon</a>")
  end

  it "puts data attributes on the anchor" do
    html = render_html(href: "/x", label: "Next", data: { action: "click->pending-add#guardVisit" })
    expect(html).to include(%(aria-label="Next" data-action="click->pending-add#guardVisit"))
  end

  it "renders a focusable, aria-disabled, faded span when href is nil" do
    html = render_html(href: nil, label: "Previous box", data: { action: "click->x#y" })
    expect(html).to start_with(%(<span role="link" tabindex="0" aria-disabled="true" aria-label="Previous box"))
    expect(html).to include("text-muted/40").and include("icon</span>")
    expect(html).not_to include("data-action")
  end

  it "renders the filled variant as a card-filled circle" do
    expect(render_html(href: "/x", label: "Back", variant: :filled)).to include("h-10 w-10").and include("bg-card")
  end

  it "rejects an unknown variant" do
    expect { render_html(href: "/x", label: "Back", variant: :bogus) }.to raise_error(KeyError)
  end
end
