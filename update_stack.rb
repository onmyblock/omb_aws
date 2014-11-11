require "aws-sdk-v1"
require "aws-sdk"
require "json"

credentials = Aws::Credentials.new(
  ENV["AWS_ACCESS_KEY_ID"],
  ENV["AWS_SECRET_ACCESS_KEY"]
)

region            = "us-west-2"
availability_zone = "us-west-2a"

client_old = AWS.config(
  access_key_id:     ENV["AWS_ACCESS_KEY_ID"],
  secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
  region:            region
)

client = Aws::CloudFormation::Client.new(
  credentials: credentials,
  region:      region
)
resource = Aws::CloudFormation::Resource.new(client: client)

@folder = "production"
def string_from_json_file(file_name)
  name = "#{@folder}/#{file_name}.json"
  if File.exists? name
    file = File.open name
    data = file.read
    file.close
    data.to_str
  else
    ""
  end
end

template_json = string_from_json_file "template"
["parameters", "mappings", "conditions", "outputs"].each do |key|
  template_json.gsub! Regexp.new("{{#{key}}}"), string_from_json_file(key)
end
resources = JSON.parse string_from_json_file("resources")
resources["AutoScalingGroup2"] = resources["AutoScalingGroup1"]
resources.delete "AutoScalingGroup1"
template_json.gsub! Regexp.new("{{resources}}"), resources.to_json

resource.stacks.each do |stack|
  stack_name   = stack.name
  stack_status = stack.stack_status
  puts stack_name
  puts stack_status
  # if stack_status == "CREATE_COMPLETE"
    response = client.update_stack(
      stack_name:    stack_name,
      template_body: template_json
      # parameters: [
      #   {
      #     parameter_key:   "AutoScalingGroupInstanceId",
      #     parameter_value: "i-cda8aec2"
      #   },
      #   {
      #     parameter_key:   "USWest2CustomImageId",
      #     parameter_value: "ami-7df0bd4d"
      #   }
      # ],
      # use_previous_template: true
    )
  # end
end

auto_scaling = AWS::AutoScaling.new
puts auto_scaling.groups.filter
