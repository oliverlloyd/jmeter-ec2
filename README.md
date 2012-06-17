# JMeter ec2 Script
-----------------------------

This shell script will allow you to run your local JMeter jmx files either using Amazon's EC2 service or you can provide it with a simple, comma-delimeted list of hosts to use. It does not use Distributed mode to run the test so it is effectively infinitely scalable (Distributed mode means all results are written to a central location which at high volumes can create a bottleneck).

By default it will launch the required hardware using Amazon EC2 (ec2 mode) using Ubuntu AMIs dynamically installing Java and Apache JMeter. In this mode you can run your test over as many instances as you wish (or are allowed to create by Amazon - the default is 20). Alternatively, you can pass in a list of pre-prepared hostnames and the test load will be distributed over these instead.

Unlike distributed mode, you do not need to adjust the test parameters to ensure even distribution of the load; the script will automatically adjust the thread counts based on how many hosts are in use. As the test is running it will collate the results from each host in real time and display an output of the Generate Summary Results listener to the screen (showing both results host by host and an aggregated view for the entire run). Once execution is complete it will download each host's jtl file and collate them all together to give a single jtl file that can be viewed using the usual JMeter listeners.


Further details and idiot-level step by step instructions:
    [http://www.http503.com/2012/jmeter-ec2/](http://www.http503.com/2012/jmeter-ec2/)


## Usage:
    ./jmeter-ec2.sh [PROJECT NAME] [NUMBER OF INSTANCES DESIRED* - optional, default is 1]

**If the property REMOTE_HOSTS is set to one or more hostnames then the NUMBER OF INSTANCES value is ignored and the given REMOTE_HOSTS will be used in place of creating new hardware on Amazon.*

IMPORTANT - There is a limit imposed by Amazon on how many instances can be run - the default is 20 instances as of Oct 2011. 

Limitations:
* You cannot have variables in the field Thread Count, this value must be numeric.
* File paths cannot be dynamic, any variables in the filepath will be ignored.


## Pre-requisits
* **An Amazon ec2 account is required** unless valid hosts are specified using REMOTE_HOSTS property.
* Amazon API tools must be installed as per Amazon's instructions (only in ec2 mode).
* Testplans should have a Generate Summary Results Listener present and enabled (no other listeners are required).


## Execution Instructions (for UNIX based OSs)
1. Create a project directory on your machine. For example: '/home/username/jmeter-ec2/'. This is the working dir for the script. Under this directory extract the file example-project.zip to give:

    `/home/username/jmeter-ec2/`
    `/home/username/jmeter-ec2/myproject/`
    `/home/username/jmeter-ec2/myproject/jmx/`
    `/home/username/jmeter-ec2/myproject/data/`
    `/home/username/jmeter-ec2/myproject/plugins/ (Optional, files placed here will be copied to /bin/lib/ext/ for each jmeter instance)`

2. Download all files from https://github.com/oliverlloyd/jmeter-ec2 and place them in the root directory (eg. /home/username/jmeter-ec2).

3. Edit the file jmeter-ec2.properties, each value listed below must be set:

    `LOCAL_HOME="[Your local project directory, created above, eg. /home/username/jmeter-ec2]"`
    The script needs to know a location remotely where it can read and write data from while it runs.
    
    `REMOTE_HOME="/tmp"` # This value can be left as the default unless you have a specific requirement to change it
    This is the location where the script will execute the test from - it is not important as it will only exist for the duration of the test.

	`AMI_ID="[A linix based AMI, eg. ami-e1e8d395]"`
	(only in ec2 mode) Recommended AMIs provided. Both Java and JMeter are installed by the script and are not required.

	`INSTANCE_TYPE="t1.micro"`
	(only in ec2 mode) This depends on the type of AMI - it must be available for the AMI used.

	`INSTANCE_SECURITYGROUP="jmeter"`
	(only in ec2 mode) The name of your security group created under your Amazon account. It must allow Port 22 to the local machine running this script.

	`PEM_FILE="olloyd-eu"`
	(only in ec2 mode) Your Amazon key file - obviously must be installed locally.

	`PEM_PATH="/Users/oliver/.ec2"`
	(only in ec2 mode) The DIRECTORY where the Amazon PEM file is located. No trailing '/'!

	`INSTANCE_AVAILABILITYZONE="eu-west-1b"`
	(only in ec2 mode) Should be a valid value for where you want the instances to launch.

	`USER="ubuntu"`
	(only in ec2 mode) Different AMIs start with different basic users. This value could be 'ec2-user', 'root', 'ubuntu' etc.

	`RUNNINGTOTAL_INTERVAL="3"`
	How often running totals are printed to the screen. Based on a count of the summariser.interval property. (If the Generate Summary Results listener is set to wait 10 seconds then every 30 (3 * 10) seconds an extra row showing an agraggated summary will be printed.) The summariser.interval property in the standard jmeter.properties file defaults to 180 seconds - in the file included with this project it is set to 15 seconds, like this we default to summary updates every 45 seconds.

	`REMOTE_HOSTS=""`
	If you do not wish to use ec2 you can provide a comma-separated list of pre-defined hosts.

	`ELASTIC_IPS=""`
	If using ec2, then you can also provide a comma-separated list of pre-defined elastic IPs. This is useful is your test needs to pass through a firewall.

	`JMETER_VERSION="apache-jmeter-2.6"`
	Allows the version to be chosen dynamically. Only works on 2.5.1, 2.6 and greater.

	DATABASE SETTINGS - optional, this functionality is not currently documented.

4. Copy your JMeter jmx file into the /jmx directory under your root project directory (LOCAL_HOME) and rename it to the same name as the directory. For example, if you created the directory `/testing/myproject` then you should name the jmx file `myproject.jmx` if you are using `LOCAL_HOME=/home/username/someproject` then the jmx file should be renamed to `someproject.jmx`

5. Copy any data files that are required by your testplan to the /data sub directory.

6. Open a termnal window and cd to the project directory you created (eg. cd /home/username/someproject).

7. Type: `./jmeter-ec2.sh someproject 1`

Where 'someproject' is the name of the project directory (and jmx file) and '1' is the number of instances you wish to spread the test over. If you have provided a list of hosts using REMOTE_HOSTS then this value is ignored and all hosts in the list will be used.


## Notes:
It is not uncommon for an instance to fail to start, this is part of using the Cloud and for that reason this script will dynamically respond to this event by adjusting the number of instances that are used for the test. For example, if you request 10 instances but 1 fails then the test will be run using only 9 machines. This should not be a problem as the load will still be evenly spread and the end results (the throughput) identical. In a similar fashion, should Amazon not provide all the instances you asked for (each accunt is limited) then the script will also adjust to this scenario.
    
Any testplan should always have suitable pacing to regulate throughput. This script distributes load based on threads, it is assumed that these threads are setup with suitable timers. If not, adding more hardware could create unpredictable results.



JMeter-ec2 is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

JMeter-ec2 is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with JMeter-ec2.  If not, see <http://www.gnu.org/licenses/>.



The source repository is at:
  [https://github.com/oliverlloyd/jmeter-ec2](https://github.com/oliverlloyd/jmeter-ec2)