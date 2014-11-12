# gem install aws-sdk --pre
require "aws-sdk"
require "aws-sdk-v1"
require "getoptlong"
require "json"

options = {
  asg_max_size:       4,
  asg_min_size:       2,
  availability_zones: ["us-west-1a"],
  cidr_block:         "10.1.0.0/16",
  environment:        "dev",
  instance_ami_id:    "ami-076e6542",
  instance_count:     2,
  key_name:           "aws_omb_us_west_1",
  nat_ami_id:         "ami-2b2b296e",
  regions:            ["us-west-1"],
  peer_vpc_cidr_blocks: nil,
  peer_vpc_ids:         nil,
  version:              nil
}

opts = GetoptLong.new(
  ["--asg_max_size", GetoptLong::OPTIONAL_ARGUMENT],
  ["--asg_min_size", GetoptLong::OPTIONAL_ARGUMENT],
  ["--availability_zones", GetoptLong::OPTIONAL_ARGUMENT],
  ["--cidr_block", GetoptLong::OPTIONAL_ARGUMENT],
  ["--environment", GetoptLong::OPTIONAL_ARGUMENT],
  ["--instance_ami_id", GetoptLong::OPTIONAL_ARGUMENT],
  ["--instance_count", GetoptLong::OPTIONAL_ARGUMENT],
  ["--key_name", GetoptLong::OPTIONAL_ARGUMENT],
  ["--nat_ami_id", GetoptLong::OPTIONAL_ARGUMENT],
  ["--peer_vpc_cidr_blocks", GetoptLong::OPTIONAL_ARGUMENT],
  ["--peer_vpc_ids", GetoptLong::OPTIONAL_ARGUMENT],
  ["--regions", GetoptLong::OPTIONAL_ARGUMENT],
  ["--version", GetoptLong::REQUIRED_ARGUMENT]
)
opts.each do |opt, arg|
  case opt
  when "--asg_max_size"
    options[:asg_max_size] = arg
  when "--asg_min_size"
    options[:asg_min_size] = arg
  when "--availability_zones"
    options[:availability_zones] = arg.split(",")
  when "--cidr_block"
    options[:cidr_block] = arg
  when "--environment"
    options[:environment] = arg
  when "--instance_ami_id"
    options[:instance_ami_id] = arg
  when "--instance_count"
    options[:instance_count] = arg
  when "--key_name"
    options[:key_name] = arg
  when "--nat_ami_id"
    options[:nat_ami_id] = arg
  when "--peer_vpc_cidr_blocks"
    options[:peer_vpc_cidr_blocks] = arg.split(",")
  when "--peer_vpc_ids"
    options[:peer_vpc_ids] = arg.split(",")
  when "--regions"
    options[:regions] = arg.split(",")
  when "--version"
    options[:version] = arg
  end
end

if options[:peer_vpc_cidr_blocks].nil? && options[:peer_vpc_ids].nil?
  options[:peer_vpc_cidr_blocks] = ["0"]
  options[:peer_vpc_ids]         = ["0"]
elsif options[:peer_vpc_cidr_blocks].nil? || options[:peer_vpc_ids].nil?
  if options[:peer_vpc_cidr_blocks].nil?
    puts "Missing argument: peer_vpc_cidr_blocks"
  else
    puts "Missing argument: peer_vpc_ids"
  end
  exit 0
end

if options[:version].nil?
  puts "Missing argument: version"
  exit 0
end

if options[:asg_max_size].to_i < options[:asg_min_size].to_i
  puts "Invalid arguments: asg_max_size cannot be larger than asg_min_size"
  exit 0
end

puts "-" * 60
puts "Parameters"
puts "-" * 30
options.each do |key, value|
  puts "#{key}: #{value}"
end

# Functions
def string_from_json_file(file_name)
  folder = "dev"
  name   = "#{folder}/#{file_name}.json"
  if File.exists? name
    file = File.open name
    data = file.read
    file.close
    data.to_str
  else
    ""
  end
end

# Load all other JSON files into 1 JSON template
template_body = string_from_json_file "template"
["parameters", "mappings", "conditions", "resources", "outputs"].each do |key|
  template_body.gsub! Regexp.new("{{#{key}}}"), string_from_json_file(key)
end

version_string = options[:version].split(".").join("-")
# Insert all variables into JSON string
[
  {
    key:   "description",
    value: "\"OnMyBlock #{options[:environment].capitalize} Stack\""
  }
].each do |hash|
  template_body.gsub! Regexp.new("{{#{hash[:key]}}}"), hash[:value]
end

# AWS Credentials used for instantiating AWS client and resources
credentials = Aws::Credentials.new(
  ENV["AWS_ACCESS_KEY_ID"],
  ENV["AWS_SECRET_ACCESS_KEY"]
)

# Loop through all regions and create stack for the region
options[:regions].each do |region|
  # CloudFormation Client
  cloudformation_client = Aws::CloudFormation::Client.new(
    credentials: credentials,
    region:      region
  )
  # CloudFormation Resource
  cloudformation_resource = Aws::CloudFormation::Resource.new(
    client: cloudformation_client
  )

  begin
    cloudformation_client.validate_template(template_body: template_body)
    stack_name = "stack-#{options[:environment]}-#{version_string}"
    stack = cloudformation_resource.create_stack(
      parameters: [
        {
          parameter_key:   "AutoScalingGroupMaxSize",
          parameter_value: options[:asg_max_size].to_s
        },
        {
          parameter_key:   "AutoScalingGroupMinSize",
          parameter_value: options[:asg_min_size].to_s
        },
        {
          parameter_key:   "AvailabilityZones",
          parameter_value: options[:availability_zones].join(",")
        },
        {
          parameter_key:   "Environment",
          parameter_value: options[:environment]
        },
        {
          parameter_key:   "InstanceAmiId",
          parameter_value: options[:instance_ami_id]
        },
        {
          parameter_key:   "InstanceCount",
          parameter_value: options[:instance_count].to_s
        },
        {
          parameter_key:   "KeyName",
          parameter_value: options[:key_name]
        },
        {
          parameter_key:   "NatAmiId",
          parameter_value: options[:nat_ami_id]
        },
        {
          parameter_key:   "PeerVpcCidrBlocks",
          parameter_value: options[:peer_vpc_cidr_blocks].join(",")
        },
        {
          parameter_key:   "PeerVpcIds",
          parameter_value: options[:peer_vpc_ids].join(",")
        },
        {
          parameter_key:   "Version",
          parameter_value: options[:version]
        },
        {
          parameter_key:   "VersionString",
          parameter_value: version_string
        },
        {
          parameter_key:   "VpcCidrBlock",
          parameter_value: options[:cidr_block]
        }
      ],
      stack_name:    stack_name,
      tags: [
        {
          key:   "Environment",
          value: options[:environment]
        },
        {
          key:   "Version",
          value: options[:version]
        }
      ],
      template_body: template_body
    )
    puts "-" * 30
    puts "Stack: #{stack.name}"
  rescue Exception => e
    puts "Error: #{e}"
  end

  # Find VPC with particular tags
  # ec2_resource.vpcs.to_a.select { |v| v.tags.to_a.detect { |tag| tag.key == "version" && tag.value == "0.0.0" } }.size
end
