class CreateBooks < ActiveRecord::Migration[8.0]
  def change
    create_table :books do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.string :author
      t.string :publisher
      t.string :cover_image_url
      t.integer :rating
      t.text :memo

      t.timestamps
    end

    add_index :books, [ :user_id, :title ]
  end
end
