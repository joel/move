# frozen_string_literal: true

require "rubocop"
require "rubocop/rspec/support"
require_relative "../../../../../lib/rubocop/cop/move/broad_rescue"

RSpec.describe RuboCop::Cop::Move::BroadRescue, :config do
  it "registers an offense for `rescue StandardError`" do
    expect_offense(<<~RUBY)
      begin
        work
      rescue StandardError
      ^^^^^^ #{described_class::MSG}
        nil
      end
    RUBY
  end

  it "registers an offense for a bare `rescue`" do
    expect_offense(<<~RUBY)
      begin
        work
      rescue
      ^^^^^^ #{described_class::MSG}
        nil
      end
    RUBY
  end

  it "registers an offense for `rescue StandardError => e`" do
    expect_offense(<<~RUBY)
      def call
        work
      rescue StandardError => e
      ^^^^^^ #{described_class::MSG}
        log(e)
      end
    RUBY
  end

  it "accepts a specific error class" do
    expect_no_offenses(<<~RUBY)
      begin
        work
      rescue ActiveRecord::StatementInvalid => e
        handle(e)
      end
    RUBY
  end

  it "accepts multiple specific error classes" do
    expect_no_offenses(<<~RUBY)
      begin
        work
      rescue Discard::RecordNotDiscarded, ActiveRecord::StatementInvalid => e
        handle(e)
      end
    RUBY
  end

  it "is silenced by an inline disable directive (the documented escape hatch)" do
    expect_no_offenses(<<~RUBY)
      begin
        work
      rescue StandardError => e # rubocop:disable Move/BroadRescue -- boundary: subscriber must not break emitter
        log(e)
      end
    RUBY
  end
end
