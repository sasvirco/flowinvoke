# flowinvoke
Operation Orchestration tool for running flows 
##Introduction
 
This script provides the ability to execute an HP Operation Orchestration flow
(http://www8.hp.com/uk/en/software-solutions/operations-orchestration-it-process-automation/) in a synchronous or asynchronous way using the rest api.
 
Script is written in perl and tested under Linux (Ubuntu) and Windows. It uses LWP and JSON to speak with the OO server, and has some command line options that allows you to specify credentials, server, flow inputs and flow uuid. There are versions in other languages, that keep the same logic and input parameters for compatibility.
 
## Installation
 
### Windows
 
On windows you need ActiveState perl. After installation, start the PPM (Perl Package Manager) and install LWP and JSON.
 
### Linux
 
Depending on your distribution you can either search your repository for lwp and json or install it through CPAN. For ubuntu that means installing with apt-get 2 packages.

```
sudo apt-get install libjson-perl
sudo apt-get install libwww-perl
sudo apt-get update
sudo apt-get upgrade
 ```

The script has a short help, which should be more than enough for start. There are some more complicated use cases below:
 ```
Usage:
    flowinvoke.pl [options]

     Options:

        --help             This help message
        --host=ip:port     The hostname of OO server. Should include port also (default: localhost:8443)
        --user             username (default: admin)
        --pass="secret"    password for the user (default: admin)
        --uuid=UUID        The UUID of the flow you want to run
        --input            Key=value pair of inputs for the flow
                           (repeat for more inputs e.g --input key1=value1 --input key2=value2)
        --encode           Encodes username and password for use with OO api. Should be in form of username:password string.
        --credentials      Use the encoded output of --encode to connect to OO instead of using the --user and --password option.
        --timeout          The time to wait for flow completion in seconds (Default: 3600 - 1hour)
        --heartbeat        Operation Orchestration polling interval (Default: 120 secs)
        --async            Run the flow in asynchronous mode (don't wait for the end result Default: synchronous)
        --verbose          By default only the flow Result is printed. Verbose will print json object that contains
                           also the flow execution summary and all bound inputs
```

## Normal Usage:

```
bash$./flowinvoke.pl --host core-oo.pslab.hp.com:8443 --input port=25 --input domain=hp.com --uuid 13dbf004-c88f-4ef6-b743-a5c6cc65d8bc --input host=10.10.0.1 --password opsware --user sas 

userIdentifier=90d96588360da0c701360da0f1d600a1
serviceInstanceId=8a8a82f34854cd660148f48a5a7a0cf3
subEndDate=2014-10-10T12:54:53+01:00
ipAddress=10.10.3.91
svcSubscriptionId=8a8a82f34854cd660148f48a53760c82
subStartDate=2014-10-09T12:54:53+01:00
Result=
bash$
 ```

That will print at the end if successful the flow outputs in a key=value pairs, suitable for shell parsing. In case you want more verbose output you can include the --verbose option, which will print instead a JSON string with the execution-log.
 
## Verbose Output:

```
bash$./flowinvoke.pl --host core-oo.pslab.hp.com:8443 --input port=25 --input domain=hp.com --uuid 13dbf004-c88f-4ef6-b743-a5c6cc65d8bc --input host=10.10.0.1 --password opsware --verbose --user admin

{
   "flowOutput" : {
     "userIdentifier" : "90d96588360da0c701360da0f1d600a1",
      "serviceInstanceId" : "8a8a82f34854cd660148f4e4b2aa1004",
      "subEndDate" : "2014-10-10T14:33:37+01:00",
      "ipAddress" : "10.10.3.92",
   },
 
 "flowInputs" : {
      "ServiceDefinitionId" : "8a8a82f3475d20c001475e41208101ad",
      "DevOpsCsaUser" : "consumer",
      "ProjectName" : "R3.5-CSA",
      "CatalogId" : "90d9650a36988e5d0136988f03ab000f",
      "Organization" : "CSA_CONSUMER"
   },
   "executionLogLevel" : "DEBUG",
   "executionSummary" : {
      "owner" : "admin",
      "pauseReason" : null,
      "roi" : 0,
      "resultStatusName" : "success",
      "status" : "COMPLETED",
      "resultStatusType" : "RESOLVED",
      "branchId" : null,
      "flowUuid" : "e0fa6a90-8cd1-4767-aa34-bfdeb004003d",
      "executionId" : "168626354",
      "endTime" : 1412858795427,
      "flowPath" : "Library/HP_DevOps/CSA/Actions/Deploy-SimpleComputeServer.xml",
      "branchesCount" : 0,
      "executionName" : "Deploy-SimpleComputeServer",
      "startTime" : 1412857892637,
      "triggeredBy" : "admin"
   },
   "flowVars" : [
      {
         "termName" : null,
         "value" : "consumer",
         "name" : "DevOpsCsaUser"
      },
      {
         "termName" : null,
         "value" : "8a8a82f3475d20c001475e41208101ad",
         "name" : "ServiceDefinitionId"
      },
      {
         "termName" : null,
         "value" : "90d9650a36988e5d0136988f03ab000f",
         "name" : "CatalogId"
      },
      {
         "termName" : null,
         "value" : "CSA_CONSUMER",
         "name" : "Organization"
      },
      {
         "termName" : null,
         "value" : "R3.5-CSA",
         "name" : "ProjectName"
      }
   ]
}
bash$
 ```

If you have noticed already, the username and password are supplied on the command line. That is not nice really, so there is a way to hide them by providing the --credentials option. Credentials is an encoded string, which is used to connect to the API, and consist of both your username and password in encoded form. To encode first your credentials run the script with --encode option:
 
## Encode Credentials

 ```
bash$./flowinvoke.pl --encode sas:sas
c2FzOnNhcw==
```

 
The string is the sas:sas (username:password) string encoded. Now I can remove the --user --password options from previous run and use --credentials instead
 
 ```
bash$./flowinvoke.pl --host core-oo.pslab.hp.com:8443 --uuid 13dbf004-c88f-4ef6-b743-a5c6cc65d8bc --input host=10.10.0.1 --input domain=hp.com--verbose --credentials c2FzOnNhcw==
```
 
## Providing Input
 
Input is provided through the --input option. If multiple inputs are required, the --input has to be specified for every key=value pair.
 
```
./flowinvoke.pl --host core-oo.pslab.hp.com:8443 --uuid 13dbf004-c88f-4ef6-b743-a5c6cc65d8bc --input host=10.10.0.1 --input domain=hp.com
```
 
In the above example the flow requires 2 inputs - host and domain.
 
## Timeout, Heartbeat and Async
 
There are 3 options with which you can control the script execution. Timeout is the total time to wait for flow to finish. The default value is 1 hour, so if your flow takes more than one hour to finish, you have to change that one.
The heartbeat on the other side is how often the script checks the flow status during execution. The default value is 2 minutes. You can decrease that if you expect your flow to finish in just seconds.
Script usually runs synchronously - e.g. runs a flow, checks the heartbeat time to finish until the timeout runs out and displays the result. If you use async option, it will run the flow and exit without waiting for the end result.

## Errors
The script will exit with non-zero status and error message unless it is not a confirmed successful run plus the following cases:
 
- The usual authentication problems - e.g. username, password is wrong
- The uuid format is wrong or non-existent
- The flow has a required input, but that has not been specified (Note that there are non-required flow inputs, that have no value assigned and Prompt you for input, in that case the flow will be in PAUSED state and exit with error)
 

## Known Issues
 
- When using --credentials, sometimes they end with ==. This might cause problems, when other input follows after (e.g redirect of the ouptut to a file with > flowoutput). To avoid that problem, make sure credentials is not your last input parameter or put the password in quotes.
