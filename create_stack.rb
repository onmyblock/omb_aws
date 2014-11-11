# gem install aws-sdk --pre
require "aws-sdk"
require "aws-sdk-v1"
require "getoptlong"
require "json"

options = {
  availability_zones: ["us-west-2a, us-west-2b"],
  cidr_block:         "10.1.0.0/16",
  environment:        "dev",
  instance_ami_id:    "ami-3d50120d",
  instance_count:     2,
  nat_ami_id:         "ami-030f4133",
  regions:            ["us-west-2"]
}

opts = GetoptLong.new(
  ["--availability_zones", GetoptLong::OPTIONAL_ARGUMENT],
  ["--cidr_block", GetoptLong::OPTIONAL_ARGUMENT],
  ["--environment", GetoptLong::OPTIONAL_ARGUMENT],
  ["--instance_count", GetoptLong::OPTIONAL_ARGUMENT],
  ["--nat_ami_id", GetoptLong::OPTIONAL_ARGUMENT],
  ["--peer_vpc_ids", GetoptLong::OPTIONAL_ARGUMENT],
  ["--regions", GetoptLong::OPTIONAL_ARGUMENT],
  ["--version", GetoptLong::REQUIRED_ARGUMENT]
)
opts.each do |opt, arg|
  case opt
  when "--availability_zones"
    options[:availability_zones] = arg.split(",")
  when "--cidr_block"
    options[:cidr_block] = arg
  when "--environment"
    options[:environment] = arg
  when "--instance_count"
    options[:instance_count] = arg
  when "--nat_ami_id"
    options[:nat_ami_id] = arg
  when "--peer_vpc_ids"
    options[:peer_vpc_ids] = arg.split(",")
  when "--regions"
    options[:regions] = arg.split(",")
  when "--version"
    options[:version] = arg
  end
end

if options[:version].nil?
  puts "Missing argument: version"
  exit 0
end

puts options

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
    stack_name = 
      "stack-#{options[:environment]}-#{options[:version].split(".").join("-")}"
    stack = cloudformation_resource.create_stack(
      parameters: [
        {
          parameter_key:   "Environment",
          parameter_value: options[:environment]
        },
        {
          parameter_key:   "NatAmiId",
          parameter_value: options[:nat_ami_id]
        },
        {
          parameter_key:   "Version",
          parameter_value: options[:version]
        },
        {
          parameter_key:   "VpcCidrBlock",
          parameter_value: options[:cidr_block]
        }
      ],
      stack_name:    stack_name,
      template_body: template_body
    )
    puts stack.name
  rescue Exception => e
    puts e
  end

  # Find VPC with particular tags
  # ec2_resource.vpcs.to_a.select { |v| v.tags.to_a.detect { |tag| tag.key == "version" && tag.value == "0.0.0" } }.size
end
