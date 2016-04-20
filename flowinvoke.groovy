import java.text.*
import java.net.*
@Grab(group='org.codehaus.groovy.modules.http-builder', 
      module='http-builder', version='0.7.2' )
import groovyx.net.http.*
import static groovy.json.JsonOutput.*
import groovyx.net.http.ContentType.*
import groovyx.net.http.Method.*

def main() {

	def cli = new CliBuilder(usage: 'flowinvoke.gy -[options]')
	cli.user(args:1, argName: 'user', 'Username (default: admin)')
	cli.password(args:1, argName: 'password', 
		'Password for the user (default:admin)')
	cli.host(args:1, argName: 'host', 
		'The hostname of OO server. Should include port also')
	cli.uuid(args:1, argName: 'uuid', 'The UUID of the flow you want to run')
	cli.encode(args:1, argName: 'string', 
		'Encodes username and password for use with OO api. \
		Should be in form of username:password string.')
	cli.timeout(args:1, argName: 'N', 
		'The time to wait for flow completion in seconds (Default: 3600 - 1hour)')
	cli.heartbeat(args:1, argName: 'N', 
		'The time to wait for flow completion in seconds (Default: 3600 - 1hour)')
	cli.async("Run the flow in asynchronous mode (don't wait for the end result\
	 Default: synchronous)")
	cli.verbose("By default only the flow Result is printed.\
		Verbose will print json object that contains slso the flow execution\
		summary and all bound inputs")
	cli.credentials(args:1, argName: 'encoded_string', 
		'Use the encoded output of --encode to connect to OO instead of using \
		the --user and --password option.')
	cli.help('print this message')
	cli.input(args:2, valueSeparator:'=', argName: 'input=value',
		'Key=value pair of inputs for the flow. Repeat for more inputs e.g. \
		--input key1=value1 --input key2=value2')

	def options = cli.parse(args)

    if (options.help) cli.usage()

	def uuid = options.uuid ?: { throw new Exception("uuid is mandatory");}
	def user = options.user ?: 'admin'
	def password = options.password ?: 'admin123'
	def host = options.host ?: 'localhost:8443'
	def timeout = options.timeout ?: 3600
	def heartbeat = options.heartbeat ?: 120
	def async = options.async ?: false
	def verbose = options.verbose ?: false
	def inputs = [:]
	def authorization

	if (options.encode)  {
		println options.encode.bytes.encodeBase64().toString()
	}

	if (options.credentials) {
		authorization = "Basic "+options.credentials.bytes.encodeBase64().toString()
	} else {
		authorization = "Basic "+"$user:$password".bytes.encodeBase64().toString()
	}

	if (options.inputs) {
		def length = options.inputs.size()
		for (i = 0; i < length;) {
 		  inputs[options.inputs[i]] = options.inputs[i+1]
 		  i += 2;
		}
	}
	
	//println "$user $password $host $uuid $timeout $heartbeat $async $verbose $authorization "
	//println inputs
    
    def http = new HTTPBuilder( 'https://'+host )
    http.headers['Authorization'] = authorization
    http.ignoreSSLIssues()
        
    def run_id = run_flow(http, uuid, inputs)
    
    if (async) {
    	return
    }

    def status = track_flow(http, run_id, timeout, heartbeat)
    def flow_result = collect_result(http, run_id)

    if (verbose) {
    	println prettyPrint(toJson(flow_result))
    } else {
    	if (flow_result.flowOutput) {
    		flow_result.flowOutput.each { n->
    			println "${n.key}=${n.value}"
    		}
    	}
    	if (status) {
    		println "Status=${status}"
    	}
    }

    if (status == "RESOLVED") {
    	return
    } 

    throw new Exception("Something went wrong")
}

def run_flow(session, uuid, inputs) {

	//collect flow information
	def path = "/oo/rest/v1/flows/" + uuid
    resp = session.get(path : path )
    def flow_name = resp['name']

    //check mandatory flow inputs
    path = "/oo/rest/v1/flows/" + uuid + "/inputs"
    resp = session.get(path : path )
    resp.each { i ->
    	if (i.mandatory == true && !inputs[i.name]) {
    		throw new Exception("missing required input ${i.name}")
    	}
    }

    //construct json post object
    def post_data = [:]
    post_data['uuid'] = uuid
    post_data['runName'] = flow_name
    post_data['logLevel'] = 'DEBUG'

    if (inputs) {
    	post_data['inputs'] = inputs
    }

    //run the flow
    path = "/oo/rest/v1/executions"
    resp = session.post(path:path, body:post_data,  requestContentType :ContentType.JSON)

    if (resp.errorCode == "NO_ERROR") {
    	return resp.executionId.toString()
    } else {
    	throw new Exception(resp.errorCode)
    }


}

def track_flow(session, run_id, timeout, heartbeat) {
    def path = "/oo/rest/v1/executions/" + run_id + "/summary"
    
    timeout = timeout.toInteger()
    heartbeat = heartbeat.toInteger()

    while(timeout  >= heartbeat ) {
    	def resp = session.get(path:path)
    	
    	if (resp[0].status == "RUNNING") {
    		sleep(heartbeat*1000)
    		timeout = timeout - heartbeat
    	} else {
    		return resp[0].resultStatusType
    	}
    }
}

def collect_result(session, run_id) {
	def path = "/oo/rest/v1/executions/" + run_id + "/execution-log"
	def resp = session.get(path:path)
	return resp
}

main()
