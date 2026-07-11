# frozen_string_literal: true

require "rails_helper"

RSpec.describe Components::Ui::SwipeActions do
  it "keeps the caller's id on the outermost element" do
    html = described_class.new(id: "review-item-42", trailing: ->(c) { c.plain "X" }).call { "Body" }
    expect(html).to match(/\A<div id="review-item-42"/)
  end

  it "merges the caller's controller tokens with swipe-actions" do
    html = described_class.new(
      data: { controller: "inline-rename highlight" }, trailing: ->(c) { c.plain "X" }
    ).call { "Body" }
    expect(html).to include('data-controller="inline-rename highlight swipe-actions"')
  end

  it "wires the before-cache teardown and focusout close on the wrapper" do
    html = described_class.new(leading: ->(c) { c.plain "X" }).call { "Body" }
    expect(html).to include("turbo:before-cache@document->swipe-actions#teardown")
    expect(html).to include("focusout->swipe-actions#closeIfFocusLeft")
  end

  it "renders the content block inside the content target with an inherited surface" do
    html = described_class.new(
      content_css: "flex items-center p-4", trailing: ->(c) { c.plain "X" }
    ).call { "ROW_CONTENT" }
    expect(html).to include("ROW_CONTENT")
    expect(html).to include('data-swipe-actions-target="content"')
    expect(html).to include("ha-swipe-content relative bg-inherit flex items-center p-4")
    expect(html).to include("focusin->swipe-actions#closeFromContent")
  end

  it "renders the leading slot in a lg-hidden layer with the focusin opener" do
    html = described_class.new(leading: ->(c) { c.plain "EDIT_SLOT" }).call { "Body" }
    expect(html).to include("EDIT_SLOT")
    expect(html).to include('data-swipe-actions-target="leading"')
    expect(html).to include("absolute inset-y-0 left-0 flex w-24 lg:hidden")
    expect(html).to include("focusin->swipe-actions#open")
  end

  it "renders the trailing slot in a lg-hidden layer with the focusin opener" do
    html = described_class.new(trailing: ->(c) { c.plain "REMOVE_SLOT" }).call { "Body" }
    expect(html).to include("REMOVE_SLOT")
    expect(html).to include('data-swipe-actions-target="trailing"')
    expect(html).to include("absolute inset-y-0 right-0 flex w-24 lg:hidden")
    expect(html).to include("focusin->swipe-actions#open")
  end

  it "renders without any swipe wiring when no slots are given" do
    html = described_class.new(id: "row-1", data: { controller: "inline-rename" }).call { "Body" }
    expect(html).not_to include("swipe-actions")
    expect(html).not_to include("ha-swipe-content")
    expect(html).to include('data-controller="inline-rename"')
    expect(html).to include("Body")
  end
end
