require 'net/http'
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

      begin

        options = response.matches[0]
        az = availability_zone(options)
        puts security_group(az)
        puts __LINE__
        puts instance_type(options)
      instance = ec2.create_instances({ image_id: coreos_image_id(az.chop, response),
                                        min_count: 1,
                                        max_count: 1,
                                        key_name: ssh_key(az),
                                        security_group_ids: security_group(az),
                                        user_data: '',
      #                                   # user_data: encoded_script,
                                        instance_type: instance_type(options),
                                        placement: { availability_zone: az },
      #                                   # subnet_id: 'SUBNET_ID',
      #                                   # iam_instance_profile: {
      #                                   #   arn: 'arn:aws:iam::' + 'ACCOUNT_ID' + ':instance-profile/aws-opsworks-ec2-role'
      #                                   # }
                                      })
      puts __LINE__
      # Wait for the instance to be created, running, and passed status checks
      ec2.client.wait_until(:instance_status_ok, {instance_ids: [instance[0].id]})
      puts __LINE__
      # Name the instance 'MyGroovyInstance' and give it the Group tag 'MyGroovyGroup'
      instance.create_tags({ tags: [{ key: 'Name', value: 'MyGroovyInstance' },
                                    { key: 'CostCenter', value: 'development' },
                                    { key: 'Owner', value: aws_user(response.user.mention_name) },
                                    { key: 'DeployedBy', value: 'lita' },
                                    { key: 'ApplicationRole', value: '6fusion-meter' }
                                   ]
                           })
      puts __LINE__
      rescue => e
        response.reply(render_template('exception', exception: e))
      end


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

    private
    def security_group(az)
      client = Aws::EC2::Client.new(region: az.chop)
      groups = client
                 .describe_security_groups
                 .security_groups
                 .find{|sg|
                   sg.ip_permissions
                     .find{|ipp|
                       ipp.to_port.eql?(22) &&
                         ipp.ip_ranges
                           .find{|ipr| ipr.cidr_ip.eql?(office_ip) } } }

      groups.sort{|a,b| a.ip_permissions.size <=> b.ip_permissions.size}.first.group_id
    end


    def ssh_key(az)
      client = Aws::EC2::Client.new(region: az.chop)
      client.describe_key_pairs.key_pairs.find{|key_pair| key_pair.key_name.match(/dev-6fusion-dev/)}.key_name
    end

    # def instance_options(str)
    #     { instance_type: get_instance_type(str),
    #       placement: { availability_zone: get_availability_zone(str) }
    #     }
    # end

    def instance_type(str)
      md = str.match(/(\p{L}{1,2}\d\.\d?(?:nano|small|medium|large|xlarge))/)
      md ? md[1] : 't2.xlarge'
    end

    def availability_zone(str)

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
        raise('not yet supported')
      else
        availability_zones.keys.select{|az| az.match(/us-\w+-\d.*/)}.reject{|az| az.match(/us-east-1/)}.sample
      end

    end


    def aws_user(mention_name)
      mapping = { 'peyton'  => 'pvaughn',
                  'd-vison' => 'dseymour',
                  'lackey'  => 'rlackey' }
      mapping[response.user.mention_name] || response.user.mention_name
    end


    # FIXME put in redis, occasionally expire
    def availability_zones
      az = redis.get('availability_zones')
      if az
        JSON::parse(az)
      else
        begin
          h = {}
          regions.each do |region|
            Aws::EC2::Client.new(region: region)
              .describe_availability_zones.data.availability_zones
              .each{|az| h[az.zone_name] = { region_name: az.region_name, state: az.state } }
          end
          redis.set('availability_zones', h.to_json)
          redis.expire('availabity_zones', 24 * 7 * 3600)
          h
        end
      end
    end

    def regions
      # expire occasionally
      @regions ||= Aws::EC2::Client.new.describe_regions.data.regions.map(&:region_name)
    end

    def office_ip
      # on the host, this IP is accessible at http://instance-data. Sadly, docker DNS doesn't seem to pick this up, so it's not available in the conatiner
      sg = Net::HTTP.get(URI.parse('http://169.254.169.254/latest/meta-data/security-groups'))

      client = Aws::EC2::Client.new
      @office_ip ||= client
                       .describe_security_groups
                       .security_groups
                       .find{|sg| sg.group_name.eql?('lita-ports')}
                       .ip_permissions
                       .find{|ipp| ipp.from_port == 22}
                       .ip_ranges
                       .first      # first/last - doesn't matter - ssh should only be open to the office IP
                       .cidr_ip
    end

    def coreos_image_id(region, response)
      redis.hget('coreos_image_id', region) ||
        begin
          response.reply("Retrieving latest CoreOS AMI for #{region}. This will take a moment... :clock3:")
          result = Aws::EC2::Client.new(region: region)
                                   .describe_images(owners:  ['aws-marketplace'],
                                                    filters: [{name: 'virtualization-type', values: ['hvm']},
                                                              {name: 'description', values: ['CoreOS*']}])
          latest = result.images.sort_by(&:creation_date).last
          redis.hset('coreos_image_id', region, latest.image_id)
          redis.expire('coreos_image_id', 24 * 7 * 3600)
          latest
        end
    end

  end
end
