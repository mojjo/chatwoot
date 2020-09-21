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

            begin
              puts "$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$"
              puts "message_id: #{message_id}"
              message = gmail.get_user_message("me", message_id, format: "full")
              process_message(gmail, message)
            rescue StandardError => e
              puts "ERROR on message #{message_id}: #{e}"
              puts e.backtrace
            end
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

  def process_message(gmail, message)
    # puts message.to_yaml

    subject = ""
    sender = ""
    recipient = ""
    failedRecipients = ""

    # Check message headers
    message.payload.headers.each do |header|
      if header.name == "Subject"
        subject = header.value
      elsif header.name == "From"
        sender = header.value
      elsif header.name == "To"
        recipient = header.value
      elsif header.name == "X-Failed-Recipients"
        failedRecipients = header.value
      end
    end

    if sender.nil? || sender.empty? || recipient.nil? || recipient.empty?
      return
    end

    if not sender.index("<").nil?
      sender = sender[sender.index("<") + 1 .. sender.length - 2];
    end

    if sender == "mailer-daemon@googlemail.com"
      # TODO: Update website to undeliverable for the recipient
      puts "Failed recipients: #{failedRecipients}"

      # website_mojjo.get('set_user_undeliverable', "email=" + failedRecipients, function() {
      #   messages.splice(0, 1);
      #   processNextMessage(context, oauth2Client, histories, maxHistoryId, messages);
      # });
      return
    end

    if not recipient.include?("support@mojjo.io") and not recipient.include?("support@mojjo.fr")
      puts "Message is not coming to the appropriate mailbox"
      return
    end

    # puts "subject: #{subject}"
    # puts "sender: #{sender}"
    # puts "recipient: #{recipient}"

    message_body = get_plain_text_from_message_parts(message.payload.parts, true).force_encoding("UTF-8")

    # puts "Body: #{message_body}"

    # Create a contact and a conversation
    inbox = Inbox.find_by_name("mojjo")

    contact = Contact.find_by_email(sender)
    if contact.nil?
      contact = Contact.create!(email: sender, account_id: inbox.account_id)
    end

    contact_inbox = ContactInbox.where(inbox_id: inbox.id, contact_id: contact.id).first
    if contact_inbox.nil?
      contact_inbox = ContactInbox.create!(inbox_id: inbox.id, contact_id: contact.id, source_id: SecureRandom.uuid)
    end

    conversation = Conversation.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: contact.id,
      contact_inbox_id: contact_inbox.id
    )

    # Create the message
    Message.create!(content: message_body, account_id: inbox.account_id, inbox_id: inbox.id, conversation: conversation, sender: contact, message_type: :incoming)

  end

  def get_plain_text_from_message_parts(message_parts, is_first)
    res = ""

    if message_parts.present? and message_parts.length > 0
      message_parts.each do |message_part|
        if not is_first and not message_part.body.nil? and not message_part.body.data.nil? and 
          (message_part.body.data.include?("support@mojjo.io") or message_part.body.data.include?("support@mojjo.fr"))
          return res
        end
        if message_part.mime_type == "text/plain"
          res += message_part.body.data
          is_first = false
        end
        if message_part.parts.present? and message_part.parts.length > 0
          res += get_plain_text_from_message_parts(message_part.parts, is_first)
        end
      end
    end

    return res
  end
end
