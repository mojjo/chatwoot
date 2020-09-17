class AddGmailTable < ActiveRecord::Migration[6.0]
  def change
    create_table 'gmail_auth', id: :serial do |t|
      t.string 'name', null: false
      t.string 'value'
    end
  end
end
