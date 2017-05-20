module Lita
  module Adapters
    class Slack < Adapter
      class API
        def send_file(room_or_user, content)
          call_api("files.upload",
                   as_user: true,
                   channels: room_or_user.id,
                   filetype: 'shell',
                   content: content)
        end
      end
    end
  end
end

module Lita
  module Adapters
    class Slack < Adapter
      class ChatService
        def send_file(target, content)
          api.send_file(target, content)
        end
      end
    end
  end
end
