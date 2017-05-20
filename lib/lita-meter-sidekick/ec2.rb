require 'aws-sdk'
require 'lita-slack'


module Lita
  module Adapters
    class Slack < Adapter
      # @api private
      class API
        def send_files(room_or_user, content)
          call_api(
            "files.upload",
            as_user: true,
            channels: room_or_user.id,
            filetype: 'shell',
            content: content
          )
        end

      end
    end
  end
end


module Lita
  module Adapters
    class Slack < Adapter
      # Slack-specific features made available to +Lita::Robot+.
      # @api public
      # @since 1.6.0
      class ChatService

        def send_file(target, content)
          api.send_file(target, content)
        end

      end
    end
  end
end

module LitaMeterSidekick
  module EC2

    def list_deployed_meters(response)
      meter_instances = []
      regions.each do |region|
        ec2 = Aws::EC2::Resource.new(region: region)
        instances = ec2.instances(filters: [{ name: 'tag:ApplicationRole', values:['6fusionMeter'] }])
        meter_instances += instances.entries
      end
      response.reply(render_template('instance_list', instances: meter_instances))
    end

    def list_instances(response, user=nil)
      instances = []
      regions.each do |region|
        ec2 = Aws::EC2::Resource.new(region: region)
        if user
          instances += ec2.instances(filters: [{ name: 'tag:Owner', values:[user] }])
        else
          instances += ec2.instances.entries
        end
      end

      content = render_template('instance_list', instances: instances)
      fallback = content.gsub('```','')
#      attachment = Lita::Adapters::Slack::Attachment.new(fallback, text: content, fallback: fallback)
 #     attachment.instance_variable_set('@text', content)

      case robot.config.robot.adapter
      when :slack then robot.chat_service.send_file(response.user, content)
      else robot.send_message(response.user, content)
      end

    end


    def regions
      @regions ||= Aws::EC2::Client.new.describe_regions.data.regions.map(&:region_name)
    end

  end
end
