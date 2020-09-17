namespace :gmail do
  desc "Show user profile"
  task :set_auth_token do
    require 'googleauth'
    require 'googleauth/stores/file_token_store'

    OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'

    scope = 'https://www.googleapis.com/auth/gmail.readonly'
    client_id = ::Google::Auth::ClientId.from_file('google_credentials.json')
    token_store = ::Google::Auth::Stores::FileTokenStore.new file: "google_token.yaml"
    authorizer = ::Google::Auth::UserAuthorizer.new(client_id, scope, token_store)

    credentials = authorizer.get_credentials(Rails.configuration.google_user_id)
    if credentials.nil?
      url = authorizer.get_authorization_url(base_url: OOB_URI )
      puts "Open #{url} in your browser and enter the resulting code:"
      code = STDIN.gets
      credentials = authorizer.get_and_store_credentials_from_code(
        user_id: Rails.configuration.google_user_id, code: code, base_url: OOB_URI)
    end
  end

  task :get_user_profile => :environment do
    begin
      require 'googleauth'
      require 'googleauth/stores/file_token_store'
      require 'google/apis/gmail_v1'

      Gmail = ::Google::Apis::GmailV1
      gmail = Gmail::GmailService.new

      scope = 'https://www.googleapis.com/auth/gmail.readonly'
      client_id = ::Google::Auth::ClientId.from_file('google_credentials.json')
      token_store = ::Google::Auth::Stores::FileTokenStore.new file: "google_token.yaml"
      authorizer = ::Google::Auth::UserAuthorizer.new(client_id, scope, token_store)
      credentials = authorizer.get_credentials(Rails.configuration.google_user_id)

      gmail.authorization = credentials

      # Show the user's labels
      result = gmail.get_user_profile("me")
      puts result.to_yaml

    rescue ::Google::Apis::ClientError => e
      puts e.to_yaml
      raise
    end
  end
end
