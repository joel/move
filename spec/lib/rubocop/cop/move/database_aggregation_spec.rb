# frozen_string_literal: true

require "rubocop"
require "rubocop/rspec/support"
require_relative "../../../../../lib/rubocop/cop/move/database_aggregation"

RSpec.describe RuboCop::Cop::Move::DatabaseAggregation, :config do
  def pluck_msg
    format(described_class::MSG, loader: "pluck(...)")
  end

  it "flags a reducer directly on `pluck`" do
    expect_offense(<<~RUBY)
      items.pluck(:n).max
      ^^^^^^^^^^^^^^^^^^^ #{pluck_msg}
    RUBY
  end

  it "flags a reducer through a `map` transform on `pluck` (the #283 shape)" do
    expect_offense(<<~RUBY)
      items.pluck(:n).map(&:to_i).max
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ #{pluck_msg}
    RUBY
  end

  it "flags a reducer on a `select` block" do
    expect_offense(<<~RUBY)
      items.select { |i| i.big? }.count
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ #{format(described_class::MSG, loader: "select { ... }")}
    RUBY
  end

  it "flags `pluck(...).tally` (Ruby-side grouped count — use group(:x).count)" do
    expect_offense(<<~RUBY)
      items.pluck(:status).tally
      ^^^^^^^^^^^^^^^^^^^^^^^^^^ #{pluck_msg}
    RUBY
  end

  it "flags an existence check on loaded rows (`pluck(...).any?` — use exists?)" do
    expect_offense(<<~RUBY)
      items.pluck(:id).any?
      ^^^^^^^^^^^^^^^^^^^^^ #{pluck_msg}
    RUBY
  end

  it "accepts a relation existence predicate (SQL `any?`/`exists?`)" do
    expect_no_offenses(<<~RUBY)
      items.where(active: true).any?
    RUBY
  end

  it "flags a reducer on a no-arg `to_a`" do
    expect_offense(<<~RUBY)
      items.to_a.size
      ^^^^^^^^^^^^^^^ #{format(described_class::MSG, loader: "to_a")}
    RUBY
  end

  it "accepts `pluck(...).map` that only reshapes (map is not a reducer)" do
    expect_no_offenses(<<~RUBY)
      items.pluck(:l, :w).map { |l, w| { l: l, w: w } }
    RUBY
  end

  it "accepts a SQL aggregate" do
    expect_no_offenses(<<~RUBY)
      items.maximum(:n)
    RUBY
  end

  it "accepts `count` on a relation" do
    expect_no_offenses(<<~RUBY)
      items.where(big: true).count
    RUBY
  end

  it "accepts a `select(:col)` projection (no block) then a SQL reducer" do
    expect_no_offenses(<<~RUBY)
      items.select(:n).sum(:n)
    RUBY
  end
end
