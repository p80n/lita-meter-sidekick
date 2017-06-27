require 'aws-sdk'
require 'lita-slack'

module LitaMeterSidekick
  module EC2

    def deploy_instance(response)
      # instance_type
      # key_name
      # image_id
      # security_groups / security_group_ids
      # user_data
      # placement { availability_zone:
      # block_device_mappings {
      # tag_specifications { [  { resource_tyep: instance, tags: [ {key: "", value: "" } ] } ] }

      response.matches[0].each{|arg|

      }

    end

    ####################################################################################################
    # List operations
    def list_deployed_meters(response)
      list_instances(response, [{ name: 'tag:ApplicationRole', values: ['6fusionMeter'] }])
    end
    def list_user_instances(response)
      list_instances(response, [{ name: 'tag:Owner', values: [aws_user(response.user.mention_name)] }])
    end
    def list_filtered_instances(response)
      tag,value = response.matches[0][0..1]
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

    # private
    def instance_options(str)
        { instance_type: get_instance_type(str),
          placement: { availability_zone: get_availability_zone(str) }
        }
    end

    def get_instance_type(str)
      md = str.match(/(\p{L}{1,2}\d\.\d?(?:small|medium|large|xlarge))/)
      md ? md[1] : 't2.xlarge'
    end

    def get_availability_zone(str)

      if md = str.match(/(\p{L}{2}-\p{L}+-\d\p{L})\b/)
        puts "md1: #{md[1]}"
        if az = availability_zones[md[1]]
          if az[:state].eql?('available')
            az
          else
            raise("Availability Zone #{az} is not currently available")
          end
        else
          raise("Availability Zone #{az} not found")
        end
      elsif md = str.match(/(\p{L}{2}-\p{L}+-\d)\b/)
        puts "md1 :: #{md[1]}"
        az, info = availability_zones.find{|k,v| v[:region_name].eql?(md[1])}
        if info
          if info[:state].eql?('available')
            az
          else
            raise("Availability Zone #{az} is not currently available")
          end
        else
          raise("Availability Zone #{az} not found")
        end
      elsif md = str.match(/(california|canada|ohio|oregon|virginia)/)

      else
        availability_zones.keys.reject{|az| az.match(/us-east-1.*/)}.sample
      end

    end


    def aws_user(mention_name)
      mapping = { 'peyton' => 'pvaughn',
                  'd-vison' => 'dseymour',
                  'lackey' => 'rlackey' }
      mapping[response.user.mention_name] || response.user.mention_name
    end

    # FIXME put in redis, occasionally expire
    def availability_zones
      az = redis.get('availability_zone')
      @availability_zones ||= begin
                                h = {}
                                regions.each do |region|
                                  Aws::EC2::Client.new(region: region).describe_availability_zones.data.availability_zones
                                    .each{|az| h[az.zone_name] = { region_name: az.region_name, state: az.state } }
                                end
                                h
                              end
    end

    def regions
      @regions ||= Aws::EC2::Client.new.describe_regions.data.regions.map(&:region_name)
    end

  end
end
