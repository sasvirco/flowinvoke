#!/usr/bin/node

// npm install node-getopt
// npm install sync-request
// npm install sleep 
// do not use sync-request for servers

//main
opt = require('node-getopt').create([
  ['' , 'user=ARG', 'username (default: admin)'],
  ['' , 'password=ARG', 'password for the user (default: admin)'],
  ['' , 'host=ARG', 'The hostname of OO server. Should include port also'],
  ['' , 'uuid=ARG', 'The UUID of the flow you want to run'],
  ['' , 'encode=ARG', 'Encodes username and password for use with OO api. Should be in form of username:password string.'],
  ['' , 'input=ARG+' , 'Key=value pair of inputs for the flow (repeat for more inputs e.g. --input key1=value1 --input key2=value2)'],
  ['' , 'timeout=ARG', 'The time to wait for flow completion in seconds (Default: 3600 - 1hour)'],
  ['' , 'heartbeat=ARG', 'Operation Orchestration polling interval (Default: 120 secs)'],
  ['' , 'async', 'Run the flow in asynchronous mode (don\'t wait for the end result Default: synchronous)'],
  ['' , 'verbose', 'By default only the flow Result is printed. Verbose will print json object that contains also the flow execution summary and all bound inputs'],
  ['' , 'credentials=ARG', 'Use the encoded output of --encode to connect to OO instead of using the --user and --password option.'],
  ['' , 'help', 'Show help and exit']
])              
.bindHelp()     
.parseSystem(); 

var uuid = opt.options.uuid ,
	user = opt.options.user || 'admin',
	password = opt.options.password || 'admin123',
	host = opt.options.host || 'localhost:8443',
	timeout = parseInt(opt.options.timeout) || 3600,
	heartbeat = parseInt(opt.options.heartbeat) || 120,
	async = opt.options.async || false,
	verbose = opt.options.verbose || false,
	inputs={},
	run_id,
	status,
	flow_result,
	a,
	i,
	authorization;

if (opt.options.encode) {
	console.log(new Buffer(opt.options.encode).toString('base64'));
	process.exit(1);
}

if (opt.options.credentials) {
	authorization = "Basic "+ new Buffer(opt.options.credentials).toString('base64');
} else {
	authorization = "Basic "+ new Buffer(user+":"+password).toString('base64');
}

if (!uuid) {
	console.log("uuid is mandatory");
	process.exit(1);
}

if (opt.options.input) {
	len = opt.options.input.length;
	for (i = 0; i < len; i++) {
		a = opt.options.input[i].split("=");
		inputs[a[0]] = a[1];
	}
}

process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';

var request = require('sync-request');
var session = {
	req : require('sync-request'),
	opt : {
		headers:  {
			'Authorization' : authorization
		}
	},
	url : host
}

run_id = run_flow(session, uuid, inputs);

if (async) {
	process.exit(1);
}

status = track_flow(session, run_id, timeout, heartbeat);
flow_result = collect_result(session, run_id);

if (verbose) {
	console.log(JSON.stringify(flow_result, null, 4));
} else {
	if (flow_result.flowOutput) {
		for (i in flow_result.flowOutput) {
			console.log(i + "=" + flow_result.flowOutput[i]);
		}
	}

	if (status) {
		console.log("Status="+status);
	}
}

if (status && status == "RESOLVED") {
	process.exit(0);
}

console.log("Something went wrong!")
console.log("Flow Summary: ");
console.log(JSON.stringify(flow_result.executionSummary, null, 4));
process.exit(1);


function run_flow(session, uuid, input) {

	var	flow_input,
		post_data = {},
		json_post,
		run_name,
		res,
		url,
		run_name;

	//collect flow information	
	url = "https://"+ session.url + "/oo/rest/v1/flows/" + uuid,
	res = session.req('GET', url, session.opt);
    run_name = JSON.parse(res.getBody().toString()).name;

    //check mandatory flow inputs
    url = url + "/inputs"
    res = session.req('GET', url, session.opt);

    flow_input = JSON.parse(res.getBody().toString());

    for (i=0; i < flow_input.length; i++) {
    	if (flow_input[i].mandatory && !input[flow_input[i].name]) {
    		console.log("ERROR: Missing required input: " + flow_input[i].name);
    		process.exit(1);
    	} else {
    		continue;
    	}
    }

    //construct json post object
    post_data['uuid'] = uuid;
    post_data['runName'] = run_name;
    post_data['logLevel'] = 'DEBUG';

    if (input) {
    	post_data['inputs'] = input;
    }

    json_post = JSON.stringify(post_data);
    
    url = 'https://' + session.url + "/oo/rest/v1/executions";

    session.opt.headers['Content-type'] = 'application/json';
    session.opt['body'] = json_post;
   
    res = session.req('POST', url, session.opt);
    
	return JSON.parse(res.getBody('utf-8')).executionId ;
}


function track_flow(session, run_id, timeout, heartbeat) {
	var res,
		sleep = require('sleep'),
		url = 'https://' + session.url + "/oo/rest/v1/executions/" + run_id + "/summary";

	while (timeout >= heartbeat) {
		res = session.req('GET', url, session.opt);

		if (JSON.parse(res.getBody().toString())[0].status == "RUNNING") {
			sleep.sleep(heartbeat);
			timeout = timeout - heartbeat;
		} else {
			return JSON.parse(res.getBody().toString())[0].resultStatusType;
		}
	}
	
}

function collect_result(session, run_id) {
	var url = 'https://' + session.url + "/oo/rest/v1/executions/" + run_id + "/execution-log",
		res = session.req('GET', url, session.opt);;

	return JSON.parse(res.getBody('utf-8').toString());
}
