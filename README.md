# JMeter ec2 Script

This shell script will allow you to run your local JMeter jmx files either using Amazon's EC2 service or you can provide it with a simple, comma-delimited list of hosts to use. Summary results are printed to the console as the script runs and then all result data is downloaded and concatenated to one file when the test completes ready for more detailed analysis offline.

By default it will launch the required hardware using Amazon EC2. Using AWS it is much easier and cheaper to scale your test over multiple slaves but if you need to you can also pass in a list of pre-prepared hostnames and the test load will be distributed over these instead. Using your own servers can be useful when the target server to be tested can not be easily accessed from a location external to your test network or you want to repeat a test iteratively.

The script does not use JMeter's Distributed Mode so you do not need to adjust the test parameters to ensure even distribution of the load; the script will automatically adjust the thread counts based on how many hosts are in use. As the test is running it will collate the results from each host in real time and display an output of the Generate Summary Results listener to the screen (showing both results host by host and an aggregated view for the entire run). Once execution is complete it will download each host's jtl file and collate them all together to give a single jtl file that can be viewed using the usual JMeter listeners.

<img width="1254" alt="jmeter-ec2-screenshot-1" src="https://cloud.githubusercontent.com/assets/1336821/14234911/df4385bc-f9e6-11e5-96fa-37230e40a670.png">

<img width="1252" alt="jmeter-ec2-screenshot-2" src="https://cloud.githubusercontent.com/assets/1336821/14234913/e4a7e516-f9e6-11e5-95a3-1152a54e46ea.png">

## Getting Started
### Prerequisites
* An Amazon ec2 account is required (unless valid hosts are specified using REMOTE_HOSTS property).
* [AWS CLI](https://aws.amazon.com/cli/) must be installed. See the  [userguide](http://docs.aws.amazon.com/cli/latest/userguide/) for setup information.
* Testplans must contain a [Generate Summary Results Listener](https://jmeter.apache.org/usermanual/component_reference.html#Generate_Summary_Results). No other listeners are required.

### Setup
 1. Create a project directory on your machine. For example: `~/Documents/WHERETOPUTMYSTUFF/`. This is where you store your testplan and any associated files.
 2. Download or clone all files from this repo into a suitable directory (e.g. `/usr/local/`).
 3. Extract the file `example-project.zip` into `~/Documents/WHERETOPUTMYSTUFF/`. You now have a template / example directory structure for your project.
 4. Edit the file jmeter-ec2.properties as below:

  `INSTANCE_SECURITYGROUP="sg-123456"`
  The ID of your security group (or groups) created under your Amazon account. It must allow Port 22 to the local machine running this script.

  `PEM_FILE="euwest1"`
  Your Amazon key file.

  `PEM_PATH="/Users/oliver/.ec2"`
  The directory (not the full filepath) where the Amazon PEM file is located. **Important**: No trailing '/'!

 5. Copy your JMeter jmx file into the /jmx directory under your root project directory (Ie. myproject) and rename it to the same name as the directory. For example, if you created the directory `/testing/myproject` then you should name the jmx file `myproject.jmx`.
 6. Copy any data files that are required by your testplan to the /data sub directory.
 7. Copy any jar files that are required by your testplan to the /plugins sub directory.
 8. Open a terminal window and cd to the project directory you created (eg. cd /home/username/someproject).
 9. Type: `count="1" ./path/to/jmeter-ec2.sh`
 Where '1' is the number of instances you wish to spread the test over. If you have provided a list of hosts using `REMOTE_HOSTS` then this value is ignored and all hosts in the list will be used.


### Advanced Usage
    percent=20 count="3" terminate="TRUE" setup="TRUE" env="UAT" release="3.23" comment="my notes" ./jmeter-ec2.sh'

    [count]           - optional, default=1
    [percent]         - optional, default=100. Should be in the format 1-100 where 20 => 20% of threads will be run by the script.
    [setup]           - optional, default=TRUE. Set to "FALSE" if a pre-defined host is being used that has already been setup (had files copied to it, jmeter installed, etc.)
    [terminate]       - optional, default=TRUE. Set to "FALSE" if the instances created should not be terminated.
    [price]           - optional, if specified spot instances will be requested at this price

### Advanced Properties

  `AMI_ID="[A linix based AMI]"`
  Recommended AMIs are provided in the jmeter-ec2.properties file. Both Java and JMeter are installed by the script dynamically if not present.

  `INSTANCE_TYPE="m3.medium"`
  `micro` type instances do work and are good for developing but they are not recommended for important test runs. Performance can be slow and you risk affecting test results.
  Note: Older generation instance types require a different type of AMI (paravirtual vs. hmv).

  `USER="ubuntu"`
  Different AMIs start with different basic users. This value could be 'ec2-user', 'root', 'admin' etc.

  `SUBNET_ID=""`
  The id of the subnet that the instance will belong to. So long as a [default VPC](http://docs.aws.amazon.com/AmazonVPC/latest/UserGuide/default-vpc.html) exists for your account you do not need to set this.

  `RUNNINGTOTAL_INTERVAL="3"`
  How often running totals are printed to the screen. Based on a count of the summariser.interval property. (If the Generate Summary Results listener is set to wait 10 seconds then every 30 (3 * 10) seconds an extra row showing an aggregated summary will be printed.) The summariser.interval property in the standard jmeter.properties file defaults to 180 seconds - in the file included with this project it is set to 15 seconds, like this we default to summary updates every 45 seconds.

  `REMOTE_HOSTS=""`
  If you do not wish to use ec2 you can provide a comma-separated list of pre-defined hosts.

  `REMOTE_PORT=""`
  Specify the port sshd is running on for `REMOTE_HOSTS` or ec2. Default 22.

  `ELASTIC_IPS=""`
  If using ec2, then you can also provide a comma-separated list of pre-defined elastic IPs. This is useful if your test needs to pass through a firewall.

  `JMETER_VERSION="apache-jmeter-2.13"`
  Allows the version to be chosen dynamically.

### Limitations:
* JMeter V3 is not tested with this script.
* There are [limits imposed by Amazon](http://docs.aws.amazon.com/general/latest/gr/aws_service_limits.html#limits_ec2) on how many instances can be run in a new account - the default is 20 instances as of Oct 2011.
* You cannot have jmeter variables in the testplan field `Thread Count`, this value must be numeric.
* Testplan file paths cannot be dynamic, any jmeter variables in the filepath will be ignored.

### Why am I seeing `copying install.sh to 1 server(s)...lost connection`?
This happens when it is not possible for the script to connect over port 22 to the instance that was created by AWS. There are a number of reasons why this can happen.

**First, can you telnet to the instance?**
Run the script to create a box but use:

`count="1" terminate="FALSE"./path/to/jmeter-ec2.sh`

Then, take the hostname of the instance just created and try:

`telnet thehostname.com 22`

If you see something like:

> Trying thehostname.com...
Connected to thehostname.com
Escape character is '^]'.
SSH-2.0-OpenSSH_6.6p1 Ubuntu-2ubuntu1

Then you **DO** have network access.

If you see:

> Trying 123.456.789.123...

You **DO NOT** have network access.

#### Things to try if you **DO** have network access

**File permissions on your PEM file**
Your .pem files [need to be secure](http://stackoverflow.com/questions/1454629/aws-ssh-access-permission-denied-publickey-issue). Use `chmod 600 yourfile.pem`.

**The `USER` property is not correct**
Different AMIs and OSs expect you to log in using different users. Make sure this value is set correctly.

**Install the latest version of the ec2-api-tools**
Check [here](http://aws.amazon.com/developertools/351/) and make sure you have the latest version installed. Use `$ ec2-version` to check.

#### Things to try if you **DO NOT** have network access

**Your Security Group is not configured properly**
The `INSTANCE_SECURITYGROUP_IDS` property needs to reference the exact ids of one or more security group that exists in the correct region and that contains a rule that allows inbound traffic on port 22 from the machine you are running the script from, or everywhere if you are running the script remotely or just want to rule this out (be sure to reduce this scope later once you've got things working)

**Check local network settings**
Often port 22 can be blocked by over-zealous local network security settings. You often see this with poor quality wifi services, the type where you have to fill out a marketing form to get access. You can sometimes get around this by using a vpn but often they block this too and then your only choice is to put down your flat white and leave.


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

### Prerequisites
* [Vagrant](http://vagrantup.com)

### Usage:
Use `jmeter-ec2.properties.vagrant` as a template for local provisioning. This file is set up to use Vagrant's ssh key, ports, etc.
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
* You may need to edit the `Vagrantfile` to meet any specific networking needs. See Vagrant's [networking documentation](http://docs.vagrantup.com/v2/getting-started/networking.html) for details.

## General Notes:
### AWS Key Pairs
To find your key pairs go to your ec2 dashboard -> Networking and Security -> Key Pairs. Make sure this key pair is in the REGION you also set in the properties file.

### AWS Security Groups
To create or check your EC2 security groups go to your ec2 dashboard -> security groups.

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
