class AgentNotifications::ConversationNotificationsMailer < ApplicationMailer
  layout 'mailer/agent'

  def conversation_creation(conversation, agent)
    # No processing here as the email will be sent by unassigned_conversation_new_message
    return
    # return unless smtp_config_set_or_development?

    # @agent = agent
    # @conversation = conversation
    # @action_url = app_account_conversation_url(account_id: @conversation.account_id, id: @conversation.display_id)
    # @message = conversation.messages.first

    # if @message.nil?
    #   return
    # end

    # mail({
    #    to: @agent.email,
    #    from: from_email,
    #    subject: "[SUPPORT] Conversation from #{@message.sender&.email} [ID - #{@conversation.display_id}]"
    #  })
  end

  def conversation_assignment(conversation, agent)
    return unless smtp_config_set_or_development?

    @agent = agent
    @conversation = conversation
    @action_url = app_account_conversation_url(account_id: @conversation.account_id, id: @conversation.display_id)
    @messages = conversation.messages.all.sort_by(&:created_at).reverse
    first_message = @messages.last
    
    mail({
       to: @agent.email,
       from: from_email,
       subject: "[SUPPORT] Conversation from #{first_message.sender&.email} [ID - #{@conversation.display_id}]"
     })
  end

  def assigned_conversation_new_message(conversation, agent)
    return unless smtp_config_set_or_development?

    @agent = agent
    @conversation = conversation
    @action_url = app_account_conversation_url(account_id: @conversation.account_id, id: @conversation.display_id)
    @messages = conversation.messages.all.sort_by(&:created_at).reverse
    first_message = @messages.last

    mail({
       to: @agent.email,
       from: from_email,
       subject: "[SUPPORT] Conversation from #{first_message.sender&.email} [ID - #{@conversation.display_id}]"
     })
  end

  def unassigned_conversation_new_message(conversation, agent)
    return unless smtp_config_set_or_development?
    
    @agent = agent
    @conversation = conversation
    @action_url = app_account_conversation_url(account_id: @conversation.account_id, id: @conversation.display_id)
    @messages = conversation.messages.all.sort_by(&:created_at).reverse
    first_message = @messages.last

    mail({
       to: @agent.email,
       from: from_email,
       subject: "[SUPPORT] Conversation from #{first_message.sender&.email} [ID - #{@conversation.display_id}]"
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
