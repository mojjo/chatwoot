class AddGmailTable < ActiveRecord::Migration[6.0]
  def change
    create_table 'gmail_histories', id: :serial do |t|
      t.bigint 'history_id', null: false
      t.datetime 'created_at', precision: 6, null: false
    end
  end
end
