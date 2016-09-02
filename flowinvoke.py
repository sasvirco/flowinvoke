#!/usr/bin/python

import json
import logging
import sys
import argparse
import requests
import requests.packages.urllib3
import time
from base64 import encodestring


def main () :

	levels = {
		'debug': logging.DEBUG,
		'info': logging.INFO,
		'warning': logging.WARNING,
		'error': logging.ERROR,
		'critical': logging.CRITICAL
	}
	
	inputs = {}

	parser = argparse.ArgumentParser(description = 'Run HP OO 10 flow from the command line')
	parser.add_argument('--user', default = 'admin', help='username (default: admin)')
	parser.add_argument('--password', default = 'admin', help='password for the user (default: admin)')
	parser.add_argument('--host', default = '16.57.70.238:8443', help='The hostname of OO server. Should include port also')
	parser.add_argument('--uuid', help='The UUID of the flow you want to run')
	parser.add_argument('--encode', help='Encodes username and password for use with OO api. Should be in form of username:password string.')
	parser.add_argument('--loglevel', default = 'INFO', help='FATAL, ERROR, WARNING, INFO, DEBUG')
	parser.add_argument('--logfile', default = 'flowinvoke.log', help='Logfile to store messages (Default: flowinvoke.log)')
	parser.add_argument('--input', action='append', help='''Key=value pair of inputs for the flow 
					   (repeat for more inputs e.g. --input key1=value1 --input key2=value2)''')
	parser.add_argument('--timeout', default = 3600, type = int, help='The time to wait for flow completion in seconds (Default: 3600 - 1hour)')
	parser.add_argument('--heartbeat', default = 120, type = int, help='Operation Orchestration polling interval (Default: 120 secs)')
	parser.add_argument('--async', action = 'store_true', help='''Run the flow in asynchronous mode (don't wait for the end result Default: synchronous)''')
	parser.add_argument('--verbose', action='store_true', help='''By default only the flow Result is printed. Verbose will print json object that contains
					   also the flow execution summary and all bound inputs''')
	parser.add_argument('--credentials', help='Use the encoded output of --encode to connect to OO instead of using the --user and --password option.')


	args = parser.parse_args()

	loglevel = levels.get(args.loglevel, logging.NOTSET)
	logging.basicConfig(
		level= args.loglevel,
		format='%(asctime)s %(name)-12s %(levelname)-8s %(message)s',
		datefmt='%m-%d %H:%M',
		filename= args.logfile,
		filemode='a')

	root = logging.getLogger()

	if (args.encode is not None) :
		print encodestring(args.encode)

	if (args.credentials is not None) :
		authorization = 'Basic '+ args.credentials
	else :
		authorization = "Basic "+ encodestring(args.user+ ":" +args.password)

	if (args.uuid is None) :
		parser.print_help()
		return

	requests.packages.urllib3.disable_warnings()
	s = requests.Session()
	s.headers.update({'Authorization': authorization})

	if args.input is not None :
		for i in args.input :
			a,b = i.split('=')
			inputs[a] = b

	run_id = run_flow(s, args.host, args.uuid, inputs)

	if (args.async is True) :
		return

	status = track_flow( s, args.host, run_id, args.timeout, args.heartbeat)
	flow_result = collect_result( s, args.host, run_id)

	if (args.verbose is True) :
		print json.dumps(flow_result, indent=4)
	else :
		if (flow_result['flowOutput']) :
			for i in flow_result['flowOutput']:
				print i + '=' + flow_result['flowOutput'][i]
		if status :
			print 'Status='+status

	if status == "RESOLVED" :
		sys.exit(0)

	raise Exception("Something went wrong\n"+json.dumps(flow_result['executionSummary'], indent=4))
	
def run_flow (s, host, uuid, input) :
	
	log = logging.getLogger()
	log.info('Entering run_flow')

	#collect flow information
	url = 'https://'+ host +'/oo/rest/v1/flows/'+ uuid
	r = s.get(url,verify=False)

	if (r.reason != 'OK') :
		raise Exception(r.reason)

	log.debug(r.text)
	flow_info = json.loads(r.text)
	
	#check mandatory flow inputs
	url = 'https://' + host + '/oo/rest/v1/flows/' + uuid + '/inputs'
	r = s.get(url,verify=False)

	if (r.reason != 'OK') :
		raise Exception (r.reason)

	log.debug(r.text)

	if (r.text) :
		flow_input = json.loads(r.text)

	for i in flow_input:
		if (i['mandatory'] is True and i['name'] not in input) :
			raise Exception('Missing required flow input: ' + i['name'])
	
	#construct json post object
	post_data = {}
	post_data['uuid'] = uuid
	post_data['runName'] = flow_info['name']
	post_data['logLevel'] = 'DEBUG'
		
	if (input is not None) :
		post_data['inputs']	 = input

	json_post = json.dumps(post_data)

	#run the flow
	url = 'https://' + host + '/oo/rest/v1/executions'
	s.headers = {'Content-type':'application/json'}
	r = s.post(url, data=json_post, verify=False)
	
	if (r.reason != 'Created') :
		log.debug(r.reason)
		raise Exception (r.reason)
	else :
		response  = json.loads(r.text)
		log.debug(response)
		return response['executionId']	


def track_flow (s, host , run_id, timeout, heartbeat) :
	
	log = logging.getLogger()
	log.info('Entering track_flow')

	poll_iterations = round(timeout/heartbeat)
	url = 'https://' + host + '/oo/rest/v1/executions/' + run_id + '/summary'

	while(poll_iterations) :
		r = s.get(url, verify=False)
		if (r.reason != 'OK'):
			raise Exception(r.reason)
	
		log.debug(r.text)
		response = json.loads(r.text)

		if (response[0]['status'] == "RUNNING"):
			time.sleep(heartbeat)
			poll_iterations = poll_iterations - 1
		else :
			return response[0]['resultStatusType']

def collect_result (s, host, run_id) :

	log = logging.getLogger()
	log.info('Entering collect_result')

	url = 'https://'+ host + '/oo/rest/v1/executions/' + run_id + '/execution-log'

	r = s.get(url, verify=False)
	if (r.reason != 'OK') :
		raise Exception(r.reason)

	log.debug(r.text)
	return json.loads(r.text)

if __name__ == "__main__":
	main()

