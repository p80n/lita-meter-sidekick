require 'aws-sdk'
require 'lita-slack'

module LitaMeterSidekick
  module EC2

    def list_deployed_meters(response)
      list_instances(response, [{ name: 'tag:ApplicationRole', values: ['6fusionMeter'] }])
    end
    def list_user_instances(response)
      owners = { 'peyton' => 'pvaughn',
                 'd-vison' => 'dseymour',
                 'lackey' => 'rlackey' }
      owner = owners[response.user.mention_name] || response.user.mention_name

      list_instances(response, [{ name: 'tag:Owner', values: [owner] }])
    end
    def list_filtered_instances(response)
      tag   = response.matches[0][0]
      value = response.matches[0][1]
      list_instances(response, [{ name: "tag:#{tag}", values: [value] }])
    end


    def list_instances(response, filters=nil)
      instances = Array.new
      # FIXME use bulk endpoint
      regions.each do |region|
        ec2 = Aws::EC2::Resource.new(region: region)
        instances += ec2.instances(filters: filters).entries
      end

      if instances.empty?
        response.reply("No matching instances found")
      else
        content = render_template('instance_list', instances: instances)
        case robot.config.robot.adapter
        when :slack then robot.chat_service.send_file(response.user, content: content, title: "EC2 Instances")
        else robot.send_message(response.user, content)
        end
      end

    end


    def regions
      @regions ||= Aws::EC2::Client.new.describe_regions.data.regions.map(&:region_name)
    end

  end
end
