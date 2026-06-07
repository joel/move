class HardenVocabularyUniquenessAndTagAppliesTo < ActiveRecord::Migration[8.1]
  # D7: tags gain an applies-to facet (item/box/both — metadata for now), and the
  # three managed vocabularies get DB-level case-insensitive name uniqueness per
  # Move (#59) — model validation alone allowed "Kitchen"/"kitchen" via races.
  def up
    add_column :tags, :applies_to, :string, null: false, default: "item"

    %i[categories tags rooms].each do |table|
      disambiguate_case_variant_names(table)
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

  private

  # Pre-flight so the unique lower(name) index can build on every tenant. A
  # tenant may already hold case-variant duplicates ("Kitchen"/"kitchen") created
  # by races before the index existed; without this, PostgreSQL would abort the
  # deploy migration. Non-destructively disambiguate the later duplicate(s) by
  # appending their id (ids are unique, so lower(name) becomes unique and no row
  # or association is lost); admins can merge them afterwards via the D7 UI.
  def disambiguate_case_variant_names(table)
    execute(<<~SQL.squish)
      WITH ranked AS (
        SELECT id,
               row_number() OVER (PARTITION BY move_id, lower(name)
                                  ORDER BY created_at, id) AS rn
        FROM #{table}
      )
      UPDATE #{table} AS t
      SET name = t.name || ' (' || t.id::text || ')'
      FROM ranked AS r
      WHERE t.id = r.id AND r.rn > 1
    SQL
  end
end
