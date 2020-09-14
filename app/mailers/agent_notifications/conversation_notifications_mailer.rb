class AgentNotifications::ConversationNotificationsMailer < ApplicationMailer
  def conversation_creation(conversation, agent)
    return unless smtp_config_set_or_development?

    @agent = agent
    @conversation = conversation
    @action_url = app_account_conversation_url(account_id: @conversation.account_id, id: @conversation.display_id)
    @message = conversation.messages.first

    mail({
       to: @agent.email,
       from: from_email,
       subject: "[SUPPORT] New conversation from #{@message.sender&.name} [ID - #{@conversation.display_id}]"
     })
  end

  def conversation_assignment(conversation, agent)
    return unless smtp_config_set_or_development?

    @agent = agent
    @conversation = conversation
    subject = "#{@agent.available_name}, A new conversation [ID - #{@conversation.display_id}] has been assigned to you."
    @action_url = app_account_conversation_url(account_id: @conversation.account_id, id: @conversation.display_id)
    send_mail_with_liquid(to: @agent.email, subject: subject) and return
  end

  def assigned_conversation_new_message(conversation, agent)
    return unless smtp_config_set_or_development?
    # Don't spam with email notifications if agent is online
    # return if ::OnlineStatusTracker.get_presence(conversation.account.id, 'User', agent.id)

    @agent = agent
    @conversation = conversation
    subject = "#{@agent.available_name}, New message in your assigned conversation [ID - #{@conversation.display_id}]."
    @action_url = app_account_conversation_url(account_id: @conversation.account_id, id: @conversation.display_id)
    send_mail_with_liquid(to: @agent.email, subject: subject) and return
  end

  def unassigned_conversation_new_message(conversation, agent)
    @agent = agent
    @conversation = conversation
    @action_url = app_account_conversation_url(account_id: @conversation.account_id, id: @conversation.display_id)
    @messages = conversation.messages.order(created_at: :desc)
    first_message = @messages.last

    mail({
       to: @agent.email,
       from: from_email,
       subject: "[SUPPORT] New conversation from #{first_message.sender&.name} [ID - #{@conversation.display_id}]"
     })
  end

  private

  def assignee_name
    @assignee_name ||= @agent&.available_name || 'Notifications'
  end

  def from_email
    "#{assignee_name} <#{ENV.fetch('MAILER_SENDER_EMAIL', 'accounts@chatwoot.com')}>"
  end
end
