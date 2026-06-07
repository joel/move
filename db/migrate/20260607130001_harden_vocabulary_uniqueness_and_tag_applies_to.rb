class HardenVocabularyUniquenessAndTagAppliesTo < ActiveRecord::Migration[8.1]
  # D7: tags gain an applies-to facet (item/box/both — metadata for now), and the
  # three managed vocabularies get DB-level case-insensitive name uniqueness per
  # Move (#59) — model validation alone allowed "Kitchen"/"kitchen" via races.
  def up
    add_column :tags, :applies_to, :string, null: false, default: "item"

    %i[categories tags rooms].each do |table|
      remove_index table, name: "index_#{table}_on_move_id_and_name"
      add_index table, "move_id, lower(name)", unique: true,
                                               name: "index_#{table}_on_move_id_and_lower_name"
    end
  end

  def down
    %i[categories tags rooms].each do |table|
      remove_index table, name: "index_#{table}_on_move_id_and_lower_name"
      add_index table, %i[move_id name], unique: true, name: "index_#{table}_on_move_id_and_name"
    end
    remove_column :tags, :applies_to
  end
end
