class GmailNewEmailJob < ApplicationJob
  require 'googleauth'
  require 'googleauth/stores/file_token_store'
  require 'google/apis/gmail_v1'

  queue_as :integrations

  def perform(history_id)
    puts "GmailNewEmailJob: history_id: #{history_id}"
    mutexName = "gmail_new_email_mutex"
    $redisMutex.del(mutexName)
    if $redisMutex.setnx(mutexName, 1)
      begin
        puts "GmailNewEmailJob: Mutex acquired"

        # Get histories after the current one
        gmail = get_gmail_service
        histories = gmail.list_user_histories("me", history_types: ["messageAdded"], label_id: "INBOX", start_history_id: history_id)

        if histories.history.present?
          histories.history.each do |history|
            # Get messages corresponding to this history
            message_id = history.messages[0].id
            message = gmail.get_user_message("me", message_id, format: "full")
            process_message(message)
          end
        else
          puts "GmailNewEmailJob: No message to process"
        end

        $redisMutex.del(mutexName)
      rescue StandardError => e
        $redisMutex.del(mutexName)
        puts "ERROR: #{e}"
        puts e.backtrace
      end
    else
      puts "GmailNewEmailJob: Cannot acquire mutex, rescheduling"
      GmailNewEmailJob.set(wait: 5.second).perform_later(history_id)
    end
  end

  def get_gmail_service
    gmail = ::Google::Apis::GmailV1::GmailService.new

    scope = 'https://www.googleapis.com/auth/gmail.readonly'
    client_id = ::Google::Auth::ClientId.from_file('google_credentials.json')
    token_store = ::Google::Auth::Stores::FileTokenStore.new file: "google_token.yaml"
    authorizer = ::Google::Auth::UserAuthorizer.new(client_id, scope, token_store)
    credentials = authorizer.get_credentials(Rails.configuration.google[:user_id])
    gmail.authorization = credentials

    return gmail
  end

  def process_message(message)
    puts message.to_yaml
  end
end
