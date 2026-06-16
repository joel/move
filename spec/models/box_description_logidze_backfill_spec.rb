# frozen_string_literal: true

require "rails_helper"

# Regression for #212. A box whose version-1 Logidze snapshot predates description
# tracking (every box created before the #210 release) must still reconstruct
# `description` correctly, so the activity-feed revert restores the prior value
# instead of silently keeping the edit. Mirrors the data repair shipped in
# db/migrate/.._backfill_box_description_in_logidze_base.rb.
RSpec.describe Box do
  # Run a statement with the Logidze trigger suppressed (so a manual log_data edit
  # isn't recomputed), then re-enable it for the rest of the transaction.
  def without_logidze(sql)
    conn = ActiveRecord::Base.connection
    conn.execute("SET LOCAL logidze.disabled = 'on'")
    conn.execute(sql)
  ensure
    conn.execute("SET LOCAL logidze.disabled = ''")
  end

  it "reconstructs a pre-tracking base snapshot as NULL after the #212 backfill" do
    box = create(:box)
    id = ActiveRecord::Base.connection.quote(box.id)
    # Simulate a box created before `description` was tracked: drop the key from
    # its version-1 changeset.
    without_logidze("UPDATE boxes SET log_data = log_data #- '{h,0,c,description}' WHERE id = #{id}")
    Boxes::Update.new.call(box:, editor: box.move.created_by, params: { description: "Set later" })

    box.reload
    # The bug: the absent base key makes Logidze keep the *current* value, so the
    # revert target reads back the edit instead of the (NULL) prior value.
    expect(box.at(version: 1).description).to eq("Set later")

    # The migration's repair: inject `description: null` into the base changeset.
    without_logidze(
      "UPDATE boxes SET log_data = jsonb_set(log_data, '{h,0,c,description}', 'null'::jsonb, true) " \
      "WHERE id = #{id} AND NOT (log_data #> '{h,0,c}' ? 'description')"
    )

    box.reload
    expect(box.at(version: 1).description).to be_nil
  end
end
