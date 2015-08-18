# JMeter ec2 Script
-----------------------------

This shell script will allow you to run your local JMeter jmx files either using Amazon's EC2 service or you can provide it with a simple, comma-delimeted list of hosts to use. Summary results are printed to the console as the script runs and then all result data is downloaded and concatenated to one file when the test completes ready for more detailed analysis offline.

By default it will launch the required hardware using Amazon EC2 (ec2 mode) using Ubuntu AMIs, dynamically installing Java and Apache JMeter. Using AWS it is much easier and cheaper to scale your test over multiple slaves but if you need to you can also pass in a list of pre-prepared hostnames and the test load will be distributed over these instead. Using your own servers can be useful when the target server to be tested can not be easily accessed from a location external to your test network.

The script does not use JMeter's Distributed Mode so you do not need to adjust the test parameters to ensure even distribution of the load; the script will automatically adjust the thread counts based on how many hosts are in use. As the test is running it will collate the results from each host in real time and display an output of the Generate Summary Results listener to the screen (showing both results host by host and an aggregated view for the entire run). Once execution is complete it will download each host's jtl file and collate them all together to give a single jtl file that can be viewed using the usual JMeter listeners.


Further details and idiot-level step by step instructions:
    [Archived here](http://web.archive.org/web/20120209090437/http://www.http503.com/2012/jmeter-ec2/)

## Usage:
    percent=20 count="3" terminate="TRUE" setup="TRUE" env="UAT" release="3.23" comment="my notes" ./jmeter-ec2.sh'

    [count]           - optional, default=1 
    [percent]         - optional, default=100. Should be in the format 1-100 where 20 => 20% of threads will be run by the script.
    [setup]           - optional, default=TRUE. Set to "FALSE" if a pre-defined host is being used that has already been setup (had files copied to it, jmeter installed, etc.)
    [terminate]       - optional, default=TRUE. Set to "FALSE" if the instances created should not be terminated.
    [price]           - optional, if specified spot instances will be requested at this price    
    [env]             - optional, this is only used in db_mode where this text is written against the results
    [release]         - optional, this is only used in db_mode where this text is written against the results
    [comment]         - optional, this is only used in db_mode where this text is written against the results


**If the property REMOTE_HOSTS is set to one or more hostnames then the NUMBER OF INSTANCES value is ignored and the given REMOTE_HOSTS will be used in place of creating new hardware on Amazon.*

IMPORTANT - There is a limit imposed by Amazon on how many instances can be run - the default is 20 instances as of Oct 2011. 

### Limitations:
* You cannot have variables in the field Thread Count, this value must be numeric.
* File paths cannot be dynamic, any variables in the filepath will be ignored.


## Prerequisites
* **An Amazon ec2 account is required** unless valid hosts are specified using REMOTE_HOSTS property.
* Amazon API tools must be installed as per Amazon's instructions (only in ec2 mode).
* Testplans should have a Generate Summary Results Listener present and enabled (no other listeners are required).


### Notes and useful links for installing the EC2 API Tools
* Download tools from [here](http://aws.amazon.com/developertools/351/).
* Good write-up [here](http://www.robertsosinski.com/2008/01/26/starting-amazon-ec2-with-mac-os-x/).

#### Example environment Vars | `vi ~/.bash_profile`
    export EC2_HOME=~/.ec2
    export PATH=$PATH:$EC2_HOME/bin
    export EC2_PRIVATE_KEY=`ls $EC2_HOME/jmeter_key.pem`
    export EC2_CERT=`ls $EC2_HOME/jmeter_cert.pem`
    export JAVA_HOME=/System/Library/Frameworks/JavaVM.framework/Home/
    export EC2_URL=https://ec2.eu-west-1.amazonaws.com


## Execution Instructions (for UNIX based OSs)
1. Create a project directory on your machine. For example: `/home/username/myproject/`.

2. Download all files from [https://github.com/oliverlloyd/jmeter-ec2](https://github.com/oliverlloyd/jmeter-ec2) and place them in a suitable directory and then extract the file example-project.zip to give a template directory structure for your project.

3. Edit the file jmeter-ec2.properties, each value listed below must be set:

  `REMOTE_HOME="/tmp"` # This value can be left as the default unless you have a specific requirement to change it
  This is the location where the script will execute the test from - it is not important as it will only exist for the duration of the test.

  `AMI_ID="[A linix based AMI, eg. ami-e1e8d395]"`
  (only in ec2 mode) Recommended AMIs provided. Both Java and JMeter are installed by the script and are not required.

  `INSTANCE_TYPE="t1.micro"`
  (only in ec2 mode) This depends on the type of AMI - it must be available for the AMI used.

  `INSTANCE_SECURITYGROUP="jmeter"`
  (only in ec2 mode) The name or ID of your security group created under your Amazon account. It must allow Port 22 to the local machine running this script. In order to use EC2-VPC, you must specify the ID of the security group.

  `PEM_FILE="olloyd-eu"`
  (only in ec2 mode) Your Amazon key file - obviously must be installed locally.

  `PEM_PATH="/Users/oliver/.ec2"`
  (only in ec2 mode) The DIRECTORY where the Amazon PEM file is located. No trailing '/'!

  `INSTANCE_AVAILABILITYZONE="eu-west-1b"`
  (only in ec2 mode) Should be a valid value for where you want the instances to launch.

  `USER="ubuntu"`
  (only in ec2 mode) Different AMIs start with different basic users. This value could be 'ec2-user', 'root', 'ubuntu' etc.

  `SUBNET_ID=""`
  (only in ec2-vpc mode) The id of the subnet that the instance will belong to.

  `RUNNINGTOTAL_INTERVAL="3"`
  How often running totals are printed to the screen. Based on a count of the summariser.interval property. (If the Generate Summary Results listener is set to wait 10 seconds then every 30 (3 * 10) seconds an extra row showing an agraggated summary will be printed.) The summariser.interval property in the standard jmeter.properties file defaults to 180 seconds - in the file included with this project it is set to 15 seconds, like this we default to summary updates every 45 seconds.

  `REMOTE_HOSTS=""`
  If you do not wish to use ec2 you can provide a comma-separated list of pre-defined hosts.

  `REMOTE_PORT=""`
  Specify the port sshd is running on for `REMOTE_HOSTS` or ec2. Default 22.

  `ELASTIC_IPS=""`
  If using ec2, then you can also provide a comma-separated list of pre-defined elastic IPs. This is useful is your test needs to pass through a firewall.

  `JMETER_VERSION="apache-jmeter-2.7"`
  Allows the version to be chosen dynamically. Only works on 2.5.1, 2.6 and greater.

  DATABASE SETTINGS - optional, this functionality is not documented.

4. Copy your JMeter jmx file into the /jmx directory under your root project directory (Ie. myproject) and rename it to the same name as the directory. For example, if you created the directory `/testing/myproject` then you should name the jmx file `myproject.jmx`.

5. Copy any data files that are required by your testplan to the /data sub directory.

6. Copy any jar files that are required by your testplan to the /plugins sub directory.

7. Open a termnal window and cd to the project directory you created (eg. cd /home/username/someproject).

8. Type: `count="1" ./path/to/jmeter-ec2.sh`

Where '1' is the number of instances you wish to spread the test over. If you have provided a list of hosts using REMOTE_HOSTS then this value is ignored and all hosts in the list will be used.

## Spot instances

By default this shell script uses on-demand instances. You can use spot instances by requesting an hourly `price` for your EC2 instances.

### Usage:
`count="3" price=0.0035  ./jmeter-ec2.sh'`

> Spot Instances allow you to name your own price for Amazon EC2 computing capacity. You simply bid on spare Amazon EC2
> instances and run them whenever your bid exceeds the current Spot Price, which varies in real-time based on supply
> and demand. The Spot Instance pricing model complements the On-Demand and Reserved Instance pricing models,
> providing potentially the most cost-effective option for obtaining compute capacity, depending on your application.

Read more at http://aws.amazon.com/ec2/purchasing-options/spot-instances/



    [price]           - optional, if specified spot instances will be requested at this price
    [count]           - optional, default=1


### Notes
If your price is too low spot requests will fail with a status ``` price-too-low ```.

To get the price history by instance type, use the ```ec2-describe-spot-price-history``` command from [AWS CLI](http://aws.amazon.com/cli/) :

For example to get current price for t1.micro instance running Linux :

```ec2-describe-spot-price-history -H --instance-type t1.micro -d Linux/UNIX -s `date +"%Y-%m-%dT%H:%M:%SZ"````


## Running locally with Vagrant
[Vagrant](http://vagrantup.com) allows you to test your jmeter-ec2 scripts locally before pushing them to ec2.

### Pre-requisits
* [Vagrant](http://vagrantup.com)

### Usage:
Use `jmeter-ec2.properties.vagrant` as a template for local provisioning. This file is setup to use Vagrants ssh key, ports, etc.
```
# backup your properties files just in case
cp jmeter-ec2.properties jmeter-ec2.properties.bak
# use the vagrant properties file
cp jmeter-ec2.properties.vagrant jmeter-ec2.properties
# start vm and provision defaultjre
vagrant up
# run your project
project="myproject" setup="TRUE" ./jmeter-ec2.sh
```

### Note
* You may need to edit the `Vagrantfile` to meet any specific networking needs. See Vagrant's [networking documentation](http://docs.vagrantup.com/v2/getting-started/networking.html) for details

## General Notes:
### Your PEM File
Your .pem files need to be secure. Use 'chmod 600'. If not you may get the following error from scp "copying install.sh to 1 server(s)...lost connection".

### AWS Key Pairs
To find your key pairs goto your ec2 dashboard -> Networking and Security -> Key Pairs. Make sure this key pair is in the REGION you also set in the properties file.

### AWS Security Groups
To create or check your EC2 security groups goto your ec2 dashboard -> security groups.

Create a security group (e.g. called jmeter) that allows inbound access on port 22 from the IP of the machine where you are running the script.

### Using AWS
It is not uncommon for an instance to fail to start, this is part of using the Cloud and for that reason this script will dynamically respond to this event by adjusting the number of instances that are used for the test. For example, if you request 10 instances but 1 fails then the test will be run using only 9 machines. This should not be a problem as the load will still be evenly spread and the end results (the throughput) identical. In a similar fashion, should Amazon not provide all the instances you asked for (each account is limited) then the script will also adjust to this scenario.

### Using Jmeter
Any testplan should always have suitable pacing to regulate throughput. This script distributes load based on threads, it is assumed that these threads are setup with suitable timers. If not, adding more hardware could create unpredictable results.


## License
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
