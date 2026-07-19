# frozen_string_literal: true

require "rails_helper"

# #702 — renderer-level checks for the private claim dossier. Thumbnails arrive
# through a duck-typed cache; a Hash-backed stand-in keeps these specs free of
# storage and vips.
RSpec.describe InsuranceDossierPdf do
  include PdfHelpers

  # fetch(media) keyed by media object (nil → nil, like the real cache).
  def fake_thumbs(map = {})
    Struct.new(:thumbs_by_media) do
      def fetch(media) = media && thumbs_by_media[media]
    end.new(map)
  end

  let(:move) { create(:move, name: "Autumn Relocation") }
  let(:room) { create(:room, move:, name: "Master Bedroom") }

  def render(sections:, thumbs: fake_thumbs, &)
    described_class.new(move: move, sections: sections, thumbnails: thumbs).render(&)
  end

  it "renders per-box headings (room or Unassigned) with every in_box item, and the warning banner" do
    box7 = create(:box, move:, number: "7", room: room)
    box9 = create(:box, move:, number: "9", room: nil)
    items7 = [create(:item, :manual, move:, box: box7, name: "Gold ring")]
    items9 = [create(:item, :manual, move:, box: box9, name: "Garden hose")]

    pdf = render(sections: [{ box: box7, items: items7 }, { box: box9, items: items9 }])

    text = document_text(pdf)
    aggregate_failures do
      expect(text).to include("Box #007 — Master Bedroom").and include("Box #009 — Unassigned")
      expect(text).to include("Gold ring").and include("Garden hose")
      expect(text).to include("Private — this dossier shows which box holds each item")
    end
  end

  it "embeds a real image for an item with a thumbnail and yields per-box progress" do
    box = create(:box, move:, number: "1", room: room)
    media = create(:media, move:, box:)
    item = create(:item, move:, box:, source_media: media, name: "Lamp")
    # A vips-encoded JPEG — what ThumbnailCache actually hands the renderer.
    jpeg = Vips::Image.black(4, 4).jpegsave_buffer(Q: 80)

    ticks = []
    pdf = render(sections: [{ box: box, items: [item] }],
                 thumbs: fake_thumbs(media => jpeg)) { |done, total| ticks << [done, total] }

    page = PDF::Reader.new(StringIO.new(pdf)).pages.last
    aggregate_failures do
      expect(page.xobjects).not_to be_empty # the thumbnail became an image XObject
      expect(ticks).to eq([[1, 1]])
    end
  end

  it "draws the placeholder for a photo-less item and for bytes Prawn rejects, never raising" do
    box = create(:box, move:, number: "1", room: room)
    no_photo = create(:item, :manual, move:, box:, name: "Loose cable")
    media = create(:media, move:, box:)
    corrupt = create(:item, move:, box:, source_media: media, name: "Blurry thing")

    pdf = nil
    expect do
      pdf = render(sections: [{ box: box, items: [no_photo, corrupt] }],
                   thumbs: fake_thumbs(media => "not-an-image"))
    end.not_to raise_error

    text = document_text(pdf)
    expect(text).to include("Loose cable").and include("Blurry thing").and include("No photo")
  end

  it "truncates a very long item name explicitly (ellipsis, never silent shrink-and-cut)" do
    box = create(:box, move:, number: "1", room: room)
    long = "Antique mahogany writing desk inherited from grandmother with brass fittings, " \
           "left drawer sticks and a small scratch on the top corner near the inkwell recess"
    item = create(:item, :manual, move:, box:, name: long)

    pdf = render(sections: [{ box: box, items: [item] }])

    text = document_text(pdf)
    expect(text).to include("Antique mahogany writing desk")
    expect(text).to include("...") # String#truncate's explicit marker
  end

  it "truncates an overlong room name in the box heading (single-line budget assumption)" do
    long_room = create(:room, move:, name: "The grand upstairs corridor cupboard beside the second bathroom door on the left")
    box = create(:box, move:, number: "1", room: long_room)
    item = create(:item, :manual, move:, box:, name: "Broom")

    text = document_text(render(sections: [{ box: box, items: [item] }]))

    expect(text).to include("Box #001 — The grand upstairs corridor")
    expect(text).not_to include("second bathroom")
  end

  it "bounds user-authored cover text (an overlong move name truncates)" do
    long_name = "Our absolutely enormous once in a lifetime intercontinental relocation " \
                "with every possession we have ever owned and then some extra descriptive text"
    big = create(:move, name: long_name)
    box = create(:box, move: big, number: "1")
    item = create(:item, :manual, move: big, box:, name: "Broom")

    text = document_text(described_class.new(move: big, sections: [{ box: box, items: [item] }],
                                             thumbnails: fake_thumbs).render).gsub(/\s+/, " ")

    expect(text).to include("Insurance Claim Dossier — Our absolutely enormous")
    expect(text).not_to include("then some extra descriptive")
  end

  it "renders Unicode item names without crashing (the #85 AFM trap)" do
    box = create(:box, move:, number: "1", room: room)
    item = create(:item, :manual, move:, box:, name: "Lámpara – Große 📦")

    expect { render(sections: [{ box: box, items: [item] }]) }.not_to raise_error
  end
end
