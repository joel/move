class AddAuthenticationToUsers < ActiveRecord::Migration[8.1]
  def change
    # Clear legacy posts first (model-free — the Post model has been removed).
    # posts.user_id has a FK to users with no cascade, so on a DB that applied
    # create_posts but not yet this migration, User.destroy_all would otherwise
    # abort on that constraint.
    execute("DELETE FROM posts") if table_exists?(:posts)
    User.destroy_all

    add_column :users, :status, :integer, null: false, default: 1

    if connection.adapter_name.downcase.include?("postgres")
      enable_extension "citext" unless extension_enabled?("citext")
      add_column :users, :email, :citext, null: false
      add_index :users, :email, unique: true, where: "status IN (1, 2)"
    else
      add_column :users, :email, :string, null: false
      add_index :users, :email, unique: true
    end
  end
end
