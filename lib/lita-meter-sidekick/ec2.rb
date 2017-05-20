require 'aws-sdk'
require 'lita-slack'

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
      attachment = Lita::Adapters::Slack::Attachment.new(content)
      target = Lita::Source.new(user: response.user)

      case robot.config.robot.adapter
      when :slack then robot.chat_service.send_attachment(target, attachment)
      else robot.send_message(target, content)
      end

    end


    def regions
      @regions ||= Aws::EC2::Client.new.describe_regions.data.regions.map(&:region_name)
    end

  end
end
