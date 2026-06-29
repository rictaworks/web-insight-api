class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users, id: :string do |t|
      t.string :google_sub, null: false
      t.string :display_name, null: false

      t.timestamps
    end

    add_index :users, :google_sub, unique: true
  end
end
