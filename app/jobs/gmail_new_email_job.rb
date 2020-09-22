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

        # Get last history id
        last_history = GmailHistory.last

        # Get histories after the current one
        gmail = get_gmail_service
        histories = gmail.list_user_histories("me", history_types: ["messageAdded"], label_id: "INBOX", 
          start_history_id: last_history.nil? ? history_id : last_history.history_id)

        puts histories.to_yaml

        if histories.history.present?
          histories.history.each do |history|
            # Get messages corresponding to this history
            message_id = history.messages[0].id

            puts "$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$"
            puts "message_id: #{message_id}"

            existing_history = GmailHistory.find_by_history_id(history.id)
            if not existing_history.nil?
              puts "History already processed"
              next
            end

            begin
              message = gmail.get_user_message("me", message_id, format: "full")
              process_message(gmail, message)
            rescue StandardError => e
              puts "ERROR on message #{message_id}: #{e}"
              puts e.backtrace
            end

            GmailHistory.create(history_id: history.id)
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

    # if sender != "vishwas@bizkonnect.com"
    #   return
    # end

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
    # puts message.to_yaml

    message_body = get_plain_text_from_message_parts(message.payload.parts, true).force_encoding("UTF-8")
    if message_body.empty?
      message_body = convert_to_text(message.payload.body.data)
    end

    # Create a contact if needed
    inbox = Inbox.find_by_name("mojjo")

    contact = Contact.find_by_email(sender)
    if contact.nil?
      contact = Contact.create!(email: sender, account_id: inbox.account_id)
    end

    contact_inbox = ContactInbox.where(inbox_id: inbox.id, contact_id: contact.id).first
    if contact_inbox.nil?
      contact_inbox = ContactInbox.create!(inbox_id: inbox.id, contact_id: contact.id, source_id: SecureRandom.uuid)
    end

    conversation = nil

    # Check if it's a reply to an existing conversation
    existing_conversation_id = subject.match(/(?<=\#)(.*)(?=\])/)
    if not existing_conversation_id.nil?
      # Find existing conversation
      conversation = Conversation.find(existing_conversation_id[1])
    end
      
    if conversation.nil?
      # Create a conversation
      conversation = Conversation.create!(
        account_id: inbox.account_id,
        inbox_id: inbox.id,
        contact_id: contact.id,
        contact_inbox_id: contact_inbox.id
      )

      # Add subject
      message_body = "Subject: " + subject + "\n\n" + message_body
    else
      # Remove replies
      message_body = EmailReplyTrimmer.trim(message_body)
    end

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

  # The objective here is to remove content after the user reply
  def filter_message_content(subject, message_content)
    # Only do that if the message is a reply to a chatwoot ticket
    return message_content
  end

  # Taken from https://github.com/alexdunae/premailer/blob/master/lib/premailer/html_to_plain_text.rb
  def convert_to_text(html, line_length = 65, from_charset = 'UTF-8')
    txt = html

    # strip text ignored html. Useful for removing
    # headers and footers that aren't needed in the
    # text version
    txt.gsub!(/<!-- start text\/html -->.*?<!-- end text\/html -->/m, '')

    # replace images with their alt attributes
    # for img tags with "" for attribute quotes
    # with or without closing tag
    # eg. the following formats:
    # <img alt="" />
    # <img alt="">
    txt.gsub!(/<img.+?alt=\"([^\"]*)\"[^>]*\>/i, '\1')

    # for img tags with '' for attribute quotes
    # with or without closing tag
    # eg. the following formats:
    # <img alt='' />
    # <img alt=''>
    txt.gsub!(/<img.+?alt=\'([^\']*)\'[^>]*\>/i, '\1')

    # links
    txt.gsub!(/<a\s.*?href=["'](mailto:)?([^"']*)["'][^>]*>((.|\s)*?)<\/a>/i) do |s|
      if $3.empty?
        ''
      else
        $3.strip + ' ( ' + $2.strip + ' )'
      end
    end

    # handle headings (H1-H6)
    txt.gsub!(/(<\/h[1-6]>)/i, "\n\\1") # move closing tags to new lines
    txt.gsub!(/[\s]*<h([1-6]+)[^>]*>[\s]*(.*)[\s]*<\/h[1-6]+>/i) do |s|
      hlevel = $1.to_i

      htext = $2
      htext.gsub!(/<br[\s]*\/?>/i, "\n") # handle <br>s
      htext.gsub!(/<\/?[^>]*>/i, '') # strip tags

      # determine maximum line length
      hlength = 0
      htext.each_line { |l| llength = l.strip.length; hlength = llength if llength > hlength }
      hlength = line_length if hlength > line_length

      case hlevel
        when 1   # H1, asterisks above and below
          htext = ('*' * hlength) + "\n" + htext + "\n" + ('*' * hlength)
        when 2   # H1, dashes above and below
          htext = ('-' * hlength) + "\n" + htext + "\n" + ('-' * hlength)
        else     # H3-H6, dashes below
          htext = htext + "\n" + ('-' * hlength)
      end

      "\n\n" + htext + "\n\n"
    end

    # wrap spans
    txt.gsub!(/(<\/span>)[\s]+(<span)/mi, '\1 \2')

    # lists -- TODO: should handle ordered lists
    txt.gsub!(/[\s]*(<li[^>]*>)[\s]*/i, '* ')
    # list not followed by a newline
    txt.gsub!(/<\/li>[\s]*(?![\n])/i, "\n")

    # paragraphs and line breaks
    txt.gsub!(/<\/p>/i, "\n\n")
    txt.gsub!(/<br[\/ ]*>/i, "\n")

    # strip remaining tags
    txt.gsub!(/<\/?[^>]*>/, '')

    # decode HTML entities
    txt = Nokogiri::HTML.parse(txt).text

    # no more than two consecutive spaces
    txt.gsub!(/ {2,}/, " ")

    txt = word_wrap(txt, line_length)

    # remove linefeeds (\r\n and \r -> \n)
    txt.gsub!(/\r\n?/, "\n")

    # strip extra spaces
    txt.gsub!(/[ \t]*\302\240+[ \t]*/, " ") # non-breaking spaces -> spaces
    txt.gsub!(/\n[ \t]+/, "\n") # space at start of lines
    txt.gsub!(/[ \t]+\n/, "\n") # space at end of lines

    # no more than two consecutive newlines
    txt.gsub!(/[\n]{3,}/, "\n\n")

    # the word messes up the parens
    txt.gsub!(/\(([ \n])(http[^)]+)([\n ])\)/) do |s|
      ($1 == "\n" ? $1 : '' ) + '( ' + $2 + ' )' + ($3 == "\n" ? $1 : '' )
    end

    txt.strip
    return txt
  end

  # Taken from Rails' word_wrap helper (http://api.rubyonrails.org/classes/ActionView/Helpers/TextHelper.html#method-i-word_wrap)
  def word_wrap(txt, line_length)
    txt.split("\n").collect do |line|
      line.length > line_length ? line.gsub(/(.{1,#{line_length}})(\s+|$)/, "\\1\n").strip : line
    end * "\n"
  end
end
