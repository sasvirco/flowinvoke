require 'optparse'
require 'ostruct'
require "base64"
require "net/https"
require "json"

def run_flow(s, uuid, input)

	#collect flow information
	path = "/oo/rest/v1/flows/" + uuid
	req, data = s.session.get(path, s.headers)
	flow_info = JSON.parse(req.body)

	#check mandatory flow inputs
	path = "/oo/rest/v1/flows/" + uuid + '/inputs'
	req, data = s.session.get(path, s.headers)
	flow_inputs = JSON.parse(req.body)

	flow_inputs.each do |i|
		if i["mandatory"] == true and !input.include? i["name"]
			abort("Missing required flow input: #{i["name"]}")
		end
	end

	#construct json post object
	post_data = {}
	post_data["uuid"] = uuid
	post_data["runName"] = flow_info["name"]
	post_data["logLevel"] = 'DEBUG'
	post_data['inputs'] ||= input

	json_post = JSON.generate(post_data)

	path = "/oo/rest/v1/executions"
	s.headers["Content-type"] = "application/json"
	req, data = s.session.post(path, json_post, s.headers)
	
	response = JSON.parse(req.body)
	return response["executionId"]
end

def track_flow(s, run_id, timeout, heartbeat)
	path = "/oo/rest/v1/executions/" + run_id + "/summary"

	while timeout >= heartbeat
		req, data = s.session.get(path, s.headers)
		response = JSON.parse(req.body)
		
		if response[0]["status"] == "RUNNING"
			sleep(heartbeat)
			timeout = timeout - heartbeat
		else 
			return response[0]["resultStatusType"]
		end
	end
end

def collect_result(s, run_id)
	path = "/oo/rest/v1/executions/" + run_id + "/execution-log"
	req, data = s.session.get(path, s.headers)
	return JSON.parse(req.body)
end

#main
if __FILE__ == $PROGRAM_NAME
	
	options = OpenStruct.new
	inputs = {}
	options.username = "admin"
	options.password = "admin"
	options.host = "localhost:8443"
	options.timeout = 3600
	options.heartbeat = 120
	options.async = false
	options.verbose = false
	options.input = []
	authorization = ""
	
	OptionParser.new do |opts|
		opts.banner = "Usage: flowinvoke.rb [options]"

		opts.on("--user [USERNAME]", String, "Username (default: admin)") { |opt| options.username = opt }
		opts.on("--password [PASSWORD]", String, "Password for the user (default:admin)") { |opt| options.password = opt }
		opts.on( "--host [HOST]", String,"The hostname of OO server. Should include port also" ) { |opt| options.host = opt }
		opts.on( "--uuid UUID","The UUID of the flow you want to run" ) { |opt| options.uuid = opt }
		opts.on( "--encode [STRING]", String,"Encodes username and password for use with OO api. 
					Should be in form of username:password string." ) { |opt| options.encode = opt }
		opts.on( "--timeout N", Integer, "The time to wait for flow completion in seconds (Default: 3600 - 1hour)" ) { |opt| options.timeout = opt }
		opts.on( "--heartbeat N", Integer, "Operation Orchestration polling interval (Default: 120 secs)" ) { |opt| options.heartbeat = opt }
		opts.on( "--async", "Run the flow in asynchronous mode (don't wait for the end result Default: synchronous)" ) { |opt| options.async = true }
		opts.on( "--verbose", "By default only the flow Result is printed. Verbose will print json object that contains
					also the flow execution summary and all bound inputs" ) { |opt| options.verbose = true }
		opts.on("--input key=value", String, "Key=value pair of inputs for the flow. 
					Repeat for more inputs e.g. --input key1=value1 --input key2=value2") { |opt| options.input.push(opt) }
		opts.on("--credentials [STRING]", String, "Use the encoded output of --encode to connect to OO instead of using the --user and --password option.") { |opt| options.credentials = opt }
		opts.on_tail("-h","--help", "This help message") { puts opts; exit }
	end.parse!

	if options.encode
		puts Base64.encode64(options.encode)
		exit(0)
	end

	if options.credentials 
		authorization = "Basic "+options.credentials
	else
		authorization = "Basic "+ Base64.encode64(options.username+":"+options.password)
	end

	if !options.uuid
		abort("uuid is mandatory")
	end

	#create session object 
	s = OpenStruct.new
	s.session = Net::HTTP.new(options.host.split(":")[0], options.host.split(":")[1])
	s.session.use_ssl = true
	s.session.verify_mode = OpenSSL::SSL::VERIFY_NONE
	s.headers = { "Authorization" => authorization }
		
	if options.input 
		options.input.each { |i|
			a,b = i.split("=")
			inputs[a] = b
		}
	end
	
	run_id = run_flow(s, options.uuid, inputs )

	exit if options.async

	status = track_flow(s, run_id, options.timeout, options.heartbeat)
	flow_result = collect_result(s, run_id)

	if options.verbose 
		puts JSON.pretty_generate(flow_result)
	else
		if flow_result["flowOutput"]
			flow_result["flowOutput"].each { |key,value| puts "#{key}=#{value}" }
		end
		
		if status
			puts "Status=#{status}"
		end
	end

	exit if status == 'RESOLVED'

	abort("Something went wrong" + JSON.pretty_generate(flow_result["executionSummary"]))

end #end main
