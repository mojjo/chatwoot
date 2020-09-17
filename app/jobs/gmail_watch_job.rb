class GmailWatchJob < ApplicationJob
  queue_as :integrations

  def perform(hook, message)
    
  end
end
