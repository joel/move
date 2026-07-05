# frozen_string_literal: true

require_relative "../../../script/self_healing/diff_stats"

RSpec.describe SelfHealing::DiffStats do
  subject(:stats) { described_class.new(diff) }

  let(:diff) do
    <<~DIFF
      diff --git a/app/actions/boxes/create.rb b/app/actions/boxes/create.rb
      --- a/app/actions/boxes/create.rb
      +++ b/app/actions/boxes/create.rb
      @@ -10,7 +10,7 @@
      -      next_number = numbers.max
      +      next_number = numbers.map(&:to_i).max
      diff --git a/spec/actions/boxes/create_spec.rb b/spec/actions/boxes/create_spec.rb
      --- a/spec/actions/boxes/create_spec.rb
      +++ b/spec/actions/boxes/create_spec.rb
      @@ -1,3 +1,9 @@
      +  it "numbers the box after the tenth" do
      +    expect(result.number).to eq(11)
      +  end
      +  specify { expect(result).to be_success }
    DIFF
  end

  it "collects added lines per file, ignoring the +++ header" do
    expect(stats.added_lines("app/actions/boxes/create.rb")).to eq(["      next_number = numbers.map(&:to_i).max"])
  end

  it "counts added examples only in spec files" do
    expect(stats.added_spec_examples).to eq(2)
  end

  it "counts added expectations only in spec files" do
    expect(stats.added_spec_expectations).to eq(2)
  end

  it "treats pack specs as spec paths and pack app code as production code" do
    expect(described_class.spec_path?("packs/labels/spec/actions/create_spec.rb")).to be(true)
    expect(described_class.spec_path?("packs/labels/app/actions/create.rb")).to be(false)
    expect(described_class.spec_path?("spec/actions/create_spec.rb")).to be(true)
  end

  it "returns an empty list for files absent from the diff" do
    expect(stats.added_lines("app/models/box.rb")).to eq([])
  end
end
