# frozen_string_literal: true

require "pdf/reader"

# Assertions on what a generated PDF actually PRINTS — as opposed to what was
# merely attempted. Prawn's shrink_to_fit truncates silently, and text painted in
# the background color extracts fine while being invisible on paper (#508), so
# byte-level checks ("%PDF", "/Count N") are not enough for content regressions.
#
# The operator-level helpers locate a text run by the hex form Prawn writes
# (<46524147494c45> Tj). That lookup assumes ASCII text in a single un-kerned run —
# true for ttfunk's MacRoman-identity subsetting of the vendored NotoSans (which has
# no legacy kern table). Non-ASCII probes, or a font whose kern table splits runs
# into TJ arrays, raise ArgumentError here loudly rather than passing vacuously:
# probe with plain-ASCII literals.
module PdfHelpers
  # The extracted text of the first page.
  def page_text(pdf)
    PDF::Reader.new(StringIO.new(pdf)).pages.first.text
  end

  # The extracted text of EVERY page joined — for whole-document invariants
  # (e.g. the insurance declaration's "no box numbers anywhere" privacy spec,
  # #702), where a first-page-only probe would pass vacuously.
  def document_text(pdf)
    PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n")
  end

  # The [r, g, b] fill color (floats, 0.0–1.0) in effect when +text+ is drawn on the
  # first page — the last fill-color operator before its text op.
  def fill_color_at(pdf, text)
    triple = content_before(pdf, text).scan(/([\d.]+ [\d.]+ [\d.]+) (?:scn|rg)/).last
    raise ArgumentError, "no RGB fill op precedes #{text.inspect}" if triple.nil?

    triple.first.split.map(&:to_f)
  end

  # The font size (pt) selected for the run that draws +text+ on the first page —
  # the last Tf operator before its text op.
  def font_size_at(pdf, text)
    size = content_before(pdf, text).scan(%r{/F[\d.]+ ([\d.]+) Tf}).last
    raise ArgumentError, "no font op precedes #{text.inspect}" if size.nil?

    size.first.to_f
  end

  private

  def content_before(pdf, text)
    content = PDF::Reader.new(StringIO.new(pdf)).pages.first.raw_content
    at = content.index("<#{text.unpack1("H*")}>")
    raise ArgumentError, "#{text.inspect} not drawn on the first page" if at.nil?

    content[0...at]
  end
end
