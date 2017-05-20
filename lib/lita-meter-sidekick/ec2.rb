require 'aws-sdk'
require 'lita-slack'

module LitaMeterSidekick
  module EC2

    def list_deployed_meters(response)
      list_instances(response, [{ name: 'tag:ApplicationRole', values:['6fusionMeter'] }])
    end

    def list_instances(response, filters=nil)
      instances = Array.new
      # FIXME use bulk endpoint
      regions.each do |region|
        ec2 = Aws::EC2::Resource.new(region: region)
#        if user
          instances += ec2.instances(filters: filters).entries #[{ name: 'tag:Owner', values:[user] }])
        # else
        #   instances += ec2.instances.entries
        # end
      end

      content = render_template('instance_list', instances: instances)

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
