# == Schema Information
#
# Table name: gmail_histories
#
#  id         :integer          not null, primary key
#  created_at :datetime         not null
#  history_id :bigint           not null
#
class GmailHistory < ApplicationRecord
end
