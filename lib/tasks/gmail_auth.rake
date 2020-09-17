namespace :gmail do
  require 'googleauth'
  require 'googleauth/stores/file_token_store'
  require 'google/apis/gmail_v1'

  desc "Setup auth token for the first time"
  task :set_auth_token do
    OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'

    scope = 'https://www.googleapis.com/auth/gmail.readonly'
    client_id = ::Google::Auth::ClientId.from_file('google_credentials.json')
    token_store = ::Google::Auth::Stores::FileTokenStore.new file: "google_token.yaml"
    authorizer = ::Google::Auth::UserAuthorizer.new(client_id, scope, token_store)
    credentials = authorizer.get_credentials(Rails.configuration.google[:user_id])

    if credentials.nil?
      url = authorizer.get_authorization_url(base_url: OOB_URI )
      puts "Open #{url} in your browser and enter the resulting code:"
      code = STDIN.gets
      credentials = authorizer.get_and_store_credentials_from_code(
        user_id: Rails.configuration.google[:user_id], code: code, base_url: OOB_URI)
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

  desc "Outputs the user profile to test gmail access"
  task :get_user_profile => :environment do
    begin
      gmail = get_gmail_service
      result = gmail.get_user_profile("me")
      puts result.to_yaml

    rescue StandardError => e
      puts e.to_yaml
      raise
    end
  end

  desc "Enables watch on a topic. Should be called only once"
  task :enable_topic_watch => :environment do
    begin
      watch_request = ::Google::Apis::GmailV1::WatchRequest.new
      watch_request.topic_name = Rails.configuration.google[:topic]

      gmail = get_gmail_service
      result = gmail.watch_user("me", watch_request)
      puts result.to_yaml

    rescue StandardError => e
      puts e.to_yaml
      raise
    end
  end

  task :refresh_auth_token => :environment do
    begin
      gmail = get_gmail_service
    rescue StandardError => e
      puts e.to_yaml
      raise
    end
  end
end