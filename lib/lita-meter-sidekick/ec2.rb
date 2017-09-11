require 'base64'
require 'net/http'
require 'yaml'

require 'aws-sdk'
require 'lita-slack'

module LitaMeterSidekick
  module EC2

    def deploy_instance(response)

      begin
         # currently hard-coded to deploy a meter. need to figure out how to update user_data, and add tags later, etc
        options = response.matches[0][0]
        az = availability_zone(options)
        response.reply("Deploying instance to #{az.chop}...")

        user_data = Base64.strict_encode64(render_template('cloud_config.yml', version: 'alpha'))
        ec2 = Aws::EC2::Resource.new(region: az.chop)

        block_device_mappings = [{ device_name: "/dev/xvda",
                                   ebs: {
                                     delete_on_termination: true,
                                     volume_size: volume_size(options),
                                     volume_type: volume_type(options) }}]
        instance_options = { image_id: coreos_image_id(az.chop, response),
                             min_count: 1,
                             max_count: 1,
                             key_name: ssh_key(az),
                             security_group_ids: [security_group(az)],
                             user_data: user_data,
                             instance_type: instance_type(options),
                             iam_instance_profile: {
                               name: "ssm-full-access" },
                             placement: { availability_zone: az },
                             block_device_mappings: block_device_mappings }

        instance_options.merge!(subnet_id: subnet(options))
        instances = ec2.create_instances(instance_options)
        # Wait for the instance to be created, running, and passed status checks
        ec2.client.wait_until(:instance_running, {instance_ids: [instances[0].id]}){|w|
          w.interval = 10
          w.max_attempts = 100
          response.reply("Waiting for instance #{instances[0].id} to spin up...") }

        aws_user = aws_user_for(response.user.mention_name)
        instances.batch_create_tags({ tags: [{ key: 'Name', value: "6fusion Meter (#{aws_user}-#{deploy_count(aws_user)})" },
                                             { key: 'CostCenter', value: 'development' },
                                             { key: 'Owner', value: aws_user_for(response.user.mention_name) },
                                             { key: 'DeployedBy', value: 'lita' },
                                             { key: 'ApplicationRole', value: '6fusion-meter' }
                                            ]})
        instance = Aws::EC2::Instance.new(instances.first.id, client: ec2.client)
        response.reply("Instance running. You can connect with:\n\n`ssh -i #{ssh_key(az)}.pem core@#{instance.public_dns_name}`\n\nMeter installation will begin after instance status checks complete...")

        # Wait for the instance to be created, running, and passed status checks
        ec2.client.wait_until(:instance_status_ok, {instance_ids: [instances[0].id]}){}
        response.reply("Meter installation underway...")

        instance
      rescue => e
        p e if e.message.match(/Encoded authorization failure/)
        response.reply(render_template('exception', exception: e))
        raise e
      end
    end

    def deploy_count(user)
      redis.incr("#{user}-deploy-count")
    end

    def deploy_meter(response)
      instance = deploy_instance(response)
      options = response.matches[0][0]
      az = availability_zone(options)
      ssm = Aws::SSM::Client.new(region: az.chop)

  # - path: "/root/install-meter"
  #   permissions: "0755"
  #   owner: "root"
  #   content: |
  #     #!/bin/sh
  #     HOSTNAME=$(curl -s http://instance-data/latest/meta-data/public-hostname)
  #     PUBLIC_IP=$(curl -s http://instance-data/latest/meta-data/public-ipv4)
  #     PRIVATE_IP=$(curl -s http://instance-data/latest/meta-data/local-ipv4)
  #     PATH=$PATH:/opt/bin END_USER_LICENSE_ACCEPTED=yes /opt/bin/meterctl install-master -f $HOSTNAME -P $PUBLIC_IP -p $PRIVATE_IP | tee /dev/console
  #     echo begin kubeconfig
  #     /usr/bin/sed -r 's|(^.+-authority): (.+)|printf "\1-data: %s" $(base64 -w0 \2)|e; s|(^.+-certificate: )(.+)|printf "    client-certificate-data: %s" $(base64 -w0 \2)|e;   s|(^ *client-key: )(.+)|printf "    client-key-data: %s" $(base64 -w0 \2)|e;'   /root/.kube/config | tee /dev/console
  #     echo end kubeconfig
  #     PATH=$PATH:/opt/bin /opt/bin/meterctl install-completion

      c = { instance_ids: [instance.id],
            document_name: 'AWS-RunShellScript',
            comment: '6fusion Meter installation',
            parameters: {
              commands: ['END_USER_LICENSE_ACCEPTED=yes /opt/bin/meterctl-alpha install-master'] } }

      response = ssm.send_command(c)

      ssm.wait_until{|waiter| p waiter;
        response.command.status == 'Success' }

      p "waiter done"

      c = { instance_ids: [instance.id],
            document_name: 'AWS-RunShellScript',
            comment: '6fusion Meter installation',
            parameters: {
              commands: ['pgrep meterctl'] } }
      install_complete = false
i = 0
      while !install_complete
        sleep 10
        i += 1
        response = ssm.send_command(c)

        resp = ssm.get_command_invocation({ command_id: response.command.id,
                                            instance_id: instance.id })
        p resp
        install_complete = resp.standard_output_content.empty?
        break if i == 10
      end

#resp.instance_association_status_infos[0].output_url.s3_output_url.output_url #=> String


      c = { instance_ids: [instance.id],
            document_name: 'AWS-RunShellScript',
            comment: '6fusion Meter installation',
            parameters: {
              commands: ['END_USER_LICENSE_ACCEPTED=yes /opt/bin/meterctl-alpha install-master'] } }


      c = { instance_ids: [instance.id],
            document_name: 'AWS-RunShellScript',
            comment: '6fusion Meter kubeconfig',
            output_s3_bucket_name: '6fusion-dev-lita',
            output_s3_key_prefix: 'meter-installs',
            parameters: {
              commands: ['/opt/bin/kubectl config view --flatten'] } }
      response = ssm.send_command(c)

      p response
      puts "===================================================================================================="
      p response.command

# will need to sed private server: IP with public IP/host

      #   response.reply("Error installing meter: " + response.command.status_details)

      instance
    end

    def terminate_instance(response)
      instance_id = response.matches[0][0]
      ec2 = Aws::EC2::Resource.new(region: 'us-east-2') # store @ creation time in redis, retrieve; fallback to searching all of aws?

      instance = ec2.instance(instance_id)
      if instance.exists?
        case instance.state.code
        when 48  # terminated
          response.reply("Instance #{instance_id} is already terminated")
        when 64  # stopping
          response.reply("Instance #{instance_id} is shutting down")
        when 89  # stopped
          response.reply("Instance #{instance_id} is currently stopped, terminating")
          instance.terminate
        else
          instance.terminate
          response.reply("Terminating instance #{instance_id}")
        end
        else
        response.reply("Not able to find any instance with id #{instance_id}")
      end
    end

    ####################################################################################################
    # List operations
    def list_deployed_meters(response)
      list_instances(response, [{ name: 'tag:ApplicationRole', values: ['6fusionMeter'] }])
    end
    def list_user_instances(response)
      list_instances(response, [{ name: 'tag:Owner', values: [aws_user_for(response.user.mention_name)] }])
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
    def volume_size(options)
      md = options.match(/\b(\d+)gi*b/i)
      md ? md[1] : 30
    end

    def volume_type(options)
      'gp2'
    end

    def subnet(options)
      case availability_zone(options)
      when /us-east-1/ then 'subnet-1d641037'
      else nil
      end
    end


    def vpc(options)
      if md = options.match(/(vpc-\w+)/)
        md[1]
      else
        case availability_zone(options)
        when /us-east-1/ then 'vpc-08c18d6c'
        else nil
        end
      end
    end


    def security_group(az)
      client = Aws::EC2::Client.new(region: az.chop)
      groups = client
                 .describe_security_groups
                 .security_groups
                 .select{|sg|
                   sg.ip_permissions
                     .find{|ipp|
                       ipp.ip_ranges
                         .find{|ipr| ipr.cidr_ip.eql?(office_ip) } } }

      # Go with teh most restrictive security group open to the office IP. TODO: ^^ make sure there are no port restrictions? or that 22 and 443 are open?
      groups.sort{|a,b| a.ip_permissions.size <=> b.ip_permissions.size}.first.group_id
    end


    def ssh_key(az)
      client = Aws::EC2::Client.new(region: az.chop)
      client.describe_key_pairs.key_pairs.find{|key_pair| key_pair.key_name.match(/dev-6fusion-dev/)}.key_name
    end

    def instance_type(str)
      puts "Checking #{str} for instance type"
      md = str.match(/(\p{L}{1,2}\d\.\d?(?:nano|small|medium|large|xlarge))/)
      md ? md[1] : 'm4.xlarge'
    end

    def availability_zone(str)
      str = 'ohio'
      az = if md = str.match(/(\p{L}{2}-\p{L}+-\d\p{L})\b/)
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
      elsif md = str.downcase.match(/(california|canada|ohio|oregon|virginia)/)
        region = case md[1]
                 when 'california' then 'us-west-1'
                 when 'canada' then 'ca-central-1'
                 when 'ohio' then 'us-east-2'
                 when 'oregon' then 'us-west-2'
                 when 'virginia' then 'us-east-1'
                 else 'us-east-2'
                 end
        # pick a random az from the region
        availability_zones.select{|az,value| value['region_name'].eql?(region) and value['state'].eql?('available')}.keys.sample
      else
        p availability_zones.keys.select{|az| az.match(/us-\w+-\d.*/)}
        availability_zones.keys.select{|az| az.match(/us-\w+-\d.*/)}.reject{|az| az.match(/us-east-1/)}.keys.sample
      end
      az.match(/us-east-1/) ? 'us-east-1b' : az  # us-east-1 doesn't have a default vpc, and onyl 1 subnet, in this AZ
    end


    def aws_user_for(slack_user)
      mapping = { 'peyton'  => 'pvaughn',
                  'd-vison' => 'dseymour',
                  'lackey'  => 'rlackey' }
      mapping[slack_user] || slack_user
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
      redis.hget('meter_image_id', region) ||
        begin
          response.reply("Retrieving latest 6fusion Meter AMI for #{region}. This will take a moment... :clock3:")
          result = Aws::EC2::Client.new(region: region)
                     .describe_images(owners:  ['self'],
                                      filters: [{name: 'virtualization-type', values: ['hvm']},
                                                {name: 'name', values: ['6fusion Meter*']}])
          custom_images = result.images.select{|i| i.name.match(/6fusion.meter/i)}.sort_by(&:creation_date)
          latest = custom_images.empty? ? result.images.sort_by(&:creation_date).last : custom_images.last
          redis.hset('meter_image_id', region, latest.image_id)
          redis.expire('meter_image_id', 3600)
          latest.image_id
        end
    end

  end
end
