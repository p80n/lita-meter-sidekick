require 'aws-sdk'
require 'lita-slack'

module LitaMeterSidekick
  module EC2

    def list_deployed_meters(response)
      list_instances(response, [{ name: 'tag:ApplicationRole', values: ['6fusionMeter'] }])
    end
    def list_user_instances(response)
      list_instances(response, [{ name: 'tag:Owner', values: [response.user.name] }])
    end
    def list_filtered_instances(response)
      tag   = response.matches[0][0]
      value = reponse.matches[1][0]
      p tag
      p value
      list_instances(response, [{ name: "tag:#{tag}", values: [value] }])
    end


    def list_instances(response, filters=nil)
      instances = Array.new
      # FIXME use bulk endpoint
      regions.each do |region|
        ec2 = Aws::EC2::Resource.new(region: region)
        instances += ec2.instances(filters: filters).entries
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
