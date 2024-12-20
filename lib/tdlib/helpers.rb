module Tdlib
  module Helpers

    TD.configure do |config|
      config.client.api_id   = ENV['TDLIB_API_ID']
      config.client.api_hash = ENV['TDLIB_API_HASH']
    end
    TD::Api.set_log_verbosity_level 0

    extend ActiveSupport::Concern
    included do
      class_attribute :td, :client
      self.client = self.td = TD::Client.new timeout: 1.minute
    end

    def read_state
      client.on TD::Types::Update::AuthorizationState do |update|
         @state = case update.authorization_state
                  when TD::Types::AuthorizationState::WaitPhoneNumber
                    :wait_phone_number
                  when TD::Types::AuthorizationState::WaitCode
                    :wait_code
                  when TD::Types::AuthorizationState::WaitPassword
                    :wait_password
                  when TD::Types::AuthorizationState::Ready
                    :ready
                  else
                    nil
                  end
      end
    end

    def get_supergroup_members supergroup_id: ENV['REPORT_SUPERGROUP_ID']&.to_i, chat_id: ENV['REPORT_CHAT_ID']&.to_i, limit: 200
      supergroup_id ||= td.get_chat(chat_id: chat_id).value.type.supergroup_id

      total = td.get_supergroup_members(supergroup_id: supergroup_id, filter: nil, offset: 0, limit: 1).value.total_count
      pages = (total.to_f / limit).ceil
      pages.times.flat_map do |p|
        td.get_supergroup_members(
          supergroup_id: supergroup_id, filter: nil, offset: p*limit, limit: limit,
        ).value.members
      end
    end

  end
end
