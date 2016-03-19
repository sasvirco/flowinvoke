package main

import (
	"strings"
	"log"
	base64 "encoding/base64"
	"flag"
	"fmt"
	"os"
	"net/http"
	"crypto/tls"
	"io/ioutil"
	"encoding/json"
	"bytes"
	"time"
)

type inputFlags []string

type Session struct {
	Connection http.Client
	Headers map[string]string
}

type PostExecutions struct {
	Uuid string `json:"uuid"`
	RunName string `json:"runName"`
	LogLevel string `json:"logLevel"`
	Inputs map[string]string `json:"inputs"`
}

type Execution 	map[string]interface{}
type ExecutionSummary map[string]interface{}
type ExecutionLog map[string]interface{}
type Flow map[string]interface{}
type Inputs map[string]interface{}



func main() {

	var input inputFlags	

	inputs := make(map[string]string)
	user := flag.String("user", "admin", "Username")
	password := flag.String("password", "admin", "password for the user")
	host := flag.String("host", "localhost:8443", `The hostname of OO server. Should include port also`)
	uuid := flag.String("uuid", "", "The UUID of the flow you want to run")
	encode := flag.String("encode", "", 
		`Encodes username and password for use with OO api. Should be in form of username:password string.`)
	credentials := flag.String("credentials", "", 
		`Use the encoded output of --encode to connect to OO instead of using the --user and --password option.`)
	heartbeat := flag.Int("heartbeat", 120, `Operation Orchestration polling interval in seconds`)
	async := flag.Bool("async", false, `Run the flow in asynchronous mode and don't wait for the end result`)
	verbose := flag.Bool("verbose", false,`Print json object that contains the flow execution summary and all bound inputs`)
	timeout := flag.Int("timeout", 3600, `The time to wait for flow completion in seconds`)
	flag.Var(&input, "input", 
		`Key=value pair of flow input (repeat for more inputs e.g. --input key1=value1 --input key2=value2)`)

	flag.Parse()

	var encoded_str string
	var authorization string

	if *encode != "" {
		encoded_str = base64.StdEncoding.EncodeToString([]byte(*encode))
		fmt.Println(encoded_str)
		os.Exit(0)
	}

	if *credentials == "" {
		authorization = "Basic " + base64.StdEncoding.EncodeToString([]byte(*user+":"+*password))
	} else {
		authorization = "Basic " + *credentials
	}

	if *uuid == "" {
		fmt.Println("uuid is mandatory")
		os.Exit(0)
	}

	if len(input) > 0 {
		for _, j := range input {
			arr := strings.Split(j, "=")
			k, v := arr[0], arr[1]
			inputs[k] = v
		}
	}

	//accept self-signed certs
	tr := &http.Transport{
        TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
    }

    client := &http.Client{Transport: tr}

	session := &Session{ 
		Headers: map[string]string{"Authorization" : authorization},
		Connection: *client,
	}

	run_id := run_flow(*session, *host, *uuid, inputs)

	if *async {
		return
	}

	status := track_flow(*session, *host, run_id, *timeout, *heartbeat)
	flow_result := collect_result(*session, *host, run_id)

	if *verbose {
    	fmt.Printf("%s", flow_result)
	} else {
		executionLog := ExecutionLog{}

		err := json.Unmarshal(flow_result, &executionLog)
		if err != nil {
			log.Fatal(err)
		}
		
		output := executionLog["flowOutput"].(map[string]interface{})
		for key, val := range(output) {
			fmt.Printf("%s=%s", key, val)
			fmt.Println()
		}

		fmt.Println("Status="+status)
	}

	if status == "RESOLVED" {
		os.Exit(0)
	}

	os.Exit(1)
}

func run_flow(s Session, host string, uuid string, inputs map[string]string) (executionId string) {

	//collect flow information
	url := "https://" + host + "/oo/rest/v1/flows/" + uuid
	req, err := http.NewRequest("GET", url, nil)
	req.Header.Add("Authorization", s.Headers["Authorization"])
	resp, err := s.Connection.Do(req)

	if err != nil {
		log.Fatal(err)
	}

	body, err := ioutil.ReadAll(resp.Body)
	
	if err != nil {
		log.Fatal(err)
	}

	flow := Flow{}

	err = json.Unmarshal(body, &flow)
	if err != nil {
		log.Fatal(err)
	}

	//check mandatory flow inputs

	url = "https://" + host + "/oo/rest/v1/flows/" + uuid + "/inputs"
	req, err = http.NewRequest("GET", url, nil)
	req.Header.Add("Authorization", s.Headers["Authorization"])
	resp, err = s.Connection.Do(req)

	if err != nil {
		log.Fatal(err)
	}

	body, err = ioutil.ReadAll(resp.Body)
	
	if err != nil {
		log.Fatal(err)
	}

	flowInputs := []Inputs{}

	err = json.Unmarshal(body, &flowInputs)
	if err != nil {
		log.Fatal(err)
	}
	
	for i := 0 ; i < len(flowInputs); i++ {

		n := flowInputs[i]["name"].(string)
		_, ok := inputs[n]
		mandatory := flowInputs[i]["mandatory"].(bool)

		if mandatory && !ok {
			log.Fatal("Missing required flow input: " + n) 
		}
	}

	//construct json post object
	post_data := &PostExecutions{
		Uuid : uuid,
		RunName: flow["name"].(string),
		LogLevel: "DEBUG",
	}
	
	if len(inputs) > 0 {
		post_data.Inputs = inputs
	}

	json_post, err := json.Marshal(*post_data)

	if err != nil {
		log.Fatal(err)
	}

	//run the flow
	url = "https://" + host + "/oo/rest/v1/executions"
	req, err = http.NewRequest("POST", url, bytes.NewBuffer(json_post))
	req.Header.Add("Authorization", s.Headers["Authorization"])
	req.Header.Add("Content-Type", "application/json")
	resp, err = s.Connection.Do(req)

	if err != nil {
		log.Fatal(err)
	}

	body, err = ioutil.ReadAll(resp.Body)
	
	if err != nil {
		log.Fatal(err)
	}	

	execution := Execution{}

	err = json.Unmarshal(body, &execution)
	if err != nil {
		log.Fatal(err)
	}

	if execution["errorCode"].(string) == "NO_ERROR" {
		return execution["executionId"].(string)
	} else {
		log.Fatal(execution["errorCode"].(string))
	}

	return
}

func track_flow(s Session, host string , run_id string, timeout int, heartbeat int) string {

	url := "https://" + host + "/oo/rest/v1/executions/" + run_id + "/summary"

	for timeout >= heartbeat {

		req, err := http.NewRequest("GET", url, nil)
		req.Header.Add("Authorization", s.Headers["Authorization"])
		resp, err := s.Connection.Do(req)

		if err != nil {
			log.Fatal(err)
		}

		body, err := ioutil.ReadAll(resp.Body)
	
		if err != nil {
			log.Fatal(err)
		}
		
		executionSummary := []ExecutionSummary{}

		err = json.Unmarshal(body, &executionSummary)
		if err != nil {
			log.Fatal(err)
		}

		if executionSummary[0]["status"].(string) == "RUNNING" {
			time.Sleep(time.Duration(heartbeat) * time.Second)
			timeout = timeout - heartbeat
		} else {
			return executionSummary[0]["resultStatusType"].(string)
		}

	}

	return ""
}

func collect_result(s Session, host string, run_id string) []byte {

	url := "https://"+ host + "/oo/rest/v1/executions/" + run_id + "/execution-log"

	req, err := http.NewRequest("GET", url, nil)
	req.Header.Add("Authorization", s.Headers["Authorization"])
	resp, err := s.Connection.Do(req)

	if err != nil {
		log.Fatal(err)
	}

	body, err := ioutil.ReadAll(resp.Body)
	
	if err != nil {
		log.Fatal(err)
	}
		
	return body
}

func (f *inputFlags) String() string {
	return fmt.Sprint(*f)
}

func (f *inputFlags) Set(value string) error {
	*f = append(*f, value)
	return nil
}
