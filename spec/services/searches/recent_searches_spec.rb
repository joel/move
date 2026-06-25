require "rails_helper"

RSpec.describe Searches::RecentSearches do
  subject(:recent) { described_class.new(session, move) }

  let(:move) { instance_double(Move, id: 42) }
  let(:other_move) { instance_double(Move, id: 99) }
  let(:session) { {} }

  it "starts empty" do
    expect(recent.list).to eq([])
  end

  it "records a query at the front, most-recent-first" do
    recent.record("winter coats")
    recent.record("kitchen electronics")

    expect(recent.list).to eq(["kitchen electronics", "winter coats"])
  end

  it "strips and ignores blank queries" do
    recent.record("  ")
    recent.record("\t")
    expect(recent.list).to eq([])

    recent.record("  skillet  ")
    expect(recent.list).to eq(["skillet"])
  end

  it "dedupes case-insensitively, keeping the freshest casing at the front" do
    recent.record("Skillet")
    recent.record("lamp")
    recent.record("skillet")

    expect(recent.list).to eq(%w[skillet lamp])
  end

  it "caps the list at MAX, dropping the oldest" do
    (1..(described_class::MAX + 2)).each { |n| recent.record("query #{n}") }

    expect(recent.list.size).to eq(described_class::MAX)
    expect(recent.list.first).to eq("query #{described_class::MAX + 2}")
    expect(recent.list).not_to include("query 1", "query 2")
  end

  it "clamps an over-long query to MAX_BYTES bytes" do
    recent.record("x" * (described_class::MAX_BYTES + 50))

    expect(recent.list.first.bytesize).to eq(described_class::MAX_BYTES)
  end

  it "clamps multibyte queries by bytes without splitting a character" do
    # "🔦" is 4 bytes; clamping must keep whole codepoints and valid UTF-8.
    recent.record("🔦" * described_class::MAX_BYTES)
    stored = recent.list.first

    expect(stored).to be_valid_encoding
    expect(stored.bytesize).to be <= described_class::MAX_BYTES
    expect(stored.bytesize % 4).to eq(0)
  end

  it "tracks at most MAX_MOVES Moves, evicting the least-recently-used" do
    moves = (1..(described_class::MAX_MOVES + 1)).map { |n| instance_double(Move, id: n) }
    moves.each { |m| described_class.new(session, m).record("q#{m.id}") }

    expect(session[described_class::SESSION_KEY].keys.size).to eq(described_class::MAX_MOVES)
    # The first Move searched is the LRU and gets evicted; the latest survives.
    expect(described_class.new(session, moves.first).list).to eq([])
    expect(described_class.new(session, moves.last).list).to eq(["q#{moves.last.id}"])
  end

  it "promotes a re-searched Move to most-recently-used, sparing it from eviction" do
    moves = (1..described_class::MAX_MOVES).map { |n| instance_double(Move, id: n) }
    moves.each { |m| described_class.new(session, m).record("q#{m.id}") }

    # Re-search the oldest Move, then add a brand-new Move: a non-promoted Move is
    # evicted, but the re-searched one survives.
    described_class.new(session, moves.first).record("again")
    new_move = instance_double(Move, id: 999)
    described_class.new(session, new_move).record("fresh")

    expect(described_class.new(session, moves.first).list).to eq(%w[again q1])
    expect(described_class.new(session, new_move).list).to eq(["fresh"])
  end

  it "scopes the list per Move within the same session" do
    recent.record("kitchen")
    described_class.new(session, other_move).record("garage")

    expect(recent.list).to eq(["kitchen"])
    expect(described_class.new(session, other_move).list).to eq(["garage"])
  end

  it "persists into the shared session store under a tenant-scoped key" do
    recent.record("kitchen")

    key = "#{Apartment::Tenant.current}:42"
    expect(session[described_class::SESSION_KEY]).to eq(key => ["kitchen"])
  end

  it "scopes the key by tenant so a shared cookie can't leak across orgs" do
    allow(Apartment::Tenant).to receive(:current).and_return("acme")
    recent.record("acme secret")

    allow(Apartment::Tenant).to receive(:current).and_return("globex")
    expect(described_class.new(session, move).list).to eq([])

    allow(Apartment::Tenant).to receive(:current).and_return("acme")
    expect(described_class.new(session, move).list).to eq(["acme secret"])
  end
end
