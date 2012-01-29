JMeter ec2 Script
-----------------------------

This shell script will allow you to run your local JMeter jmx files using Amazon's EC2 service. It will dynamically install Java and Apache JMeter
(2.5.1) using SUSE Linux AMIs, and it will run your test over as many instances as you wish (or are allowed to create by Amazon - the default is 20)
automatically ajusting the test parameters to evenly distribute the load. It will collate the results from each host in real time and display the
output of the Generate Summary Results listener as the test is running (both per individual host and an agregated view across all hosts). Once execution
is complete it will download each host's jtl file and collate them all together to give a single jtl file that can be viewed using the usual JMeter
listeners.

TO DO:
-- Accept jmx filename as a parameter (not requiring that it be named the same as the directory)
-- Accept a list of hosts instead of launching new ones - useful for repetative testing and custom AMIs
-- Accept a list of elastic IPs to be assigned to new hosts
-- Create a feature to allow a stop request to be sent to running tests (rather than just terminating the instances)


Usage: ./jmeter-ec2.sh [PROJECT NAME] [NUMBER OF INSTANCES DESIRED]*

*IMPORTANT - There is a limit imposed by Amazon on how many instances can be run [the default is 20 instances - Oct 2011].


Pre-requisits
-- An Amazon ec2 account.
-- Amazon API tools must be installed as per Amazon's instructions.
-- Testplans should have a Generate Summary Results Listener present and enabled (no other listeners are required).


Execution Instructions (for UNIX based OSs)
1. Create a project directory on your machine. For example: '/home/username/jmeter-ec2/'. This is the working dir for the script.
    Under this directory just created, either:
        a) Create a project directory, something like: '/home/username/jmeter-ec2/myproject' and then
            below that create two sub directories named 'jmx' and 'data'. Your directory structure should look something like:

                /home/username/jmeter-ec2/
                /home/username/jmeter-ec2/myproject/
                /home/username/jmeter-ec2/myproject/jmx/
                /home/username/jmeter-ec2/myproject/data/
                
    or b) Extract the contents of the example-project.zip file.
    
    Note. '/home/username/jmeter-ec2' can be anything so long as it is accessible and specified in the properties file.

2. Download all files from https://github.com/oliverlloyd/jmeter-ec2 and place them in the root directory (eg. /home/username/jmeter-ec2).

3. Edit the file jmeter-ec2.properties, each value listed below must be set:
    LOCAL_HOME="[Your local project directory, created above, eg. /home/username/jmeter-ec2]"
        The script needs to know a location remotely where it can read and write data from while it runs.
    REMOTE_HOME="/tmp" # This value can be left as the default unless you have a specific requirement to change it
        This is the location where the script will execute the test from - it is not important as it will only exist for the duration of the test.
    AMI_ID="[A linix based AMI, eg. ami-c787bbb3]"
        This only needs to be a basic AMI, the Amazon examples work fine. Both Java and JMeter are installed by the script and are not required.
    INSTANCE_TYPE="t1.micro"
        This depends on the type of AMI - it must be available for the AMI used.
    INSTANCE_SECURITYGROUP="jmeter"
        The name of your security group created under your Amazon account. It must allow Port 22 to the local machine running this script.
    PEM_FILE="olloyd-eu"
        Your Amazon key file - obviously must be installed locally.
    PEM_PATH="/Users/oliver/.ec2"
        The DIRECTORY where the Amazon PEM file is located. No trailing '/'!
    INSTANCE_AVAILABILITYZONE="eu-west-1b"
        Should be a valid value for where you want the instances to launch.
    USER="ec2-user"
        Different AMIs start with different basic users. This value could be 'ec2-user', 'root', 'ubuntu' etc.
    FILEPATH_SEPARATOR="/"
        If you are running from a Windows machine this would need to be set to "\" - (*** This is not tested ***).
    RUNNINGTOTAL_INTERVAL="3"
        How often running totals are printed to the screen. Based on a count of the summariser.interval property. (If the Generate Summary Results
        listener is set to wait 10 seconds then every 30 (3 * 10) seconds an extra row showing an agraggated summary will be printed.) The
        summariser.interval property in the standard jmeter.properties file defaults to 180 seconds - in the file included with this project it is set to
        15 seconds, like this we default to summary updates every 45 seconds.
        
4. Copy your JMeter jmx file into the /jmx directory under your root project directory (LOCAL_HOME) and rename it to the same name as the directory.
    For example, if you created the directory'/testing/myproject' then you should name the jmx file 'myproject.jmx', if you are using
    LOCAL_HOME=/home/username/someproject then the jmx file should be renamed to 'someproject.jmx'
    
        Note. This naming convention allows the script to work seemlessly over multiple projects (so long as they are all located in the same root) but
            it would not be difficult to edit the jmeter-ec2.sh file to use a specific jmx filename.
   
5. Copy any data files that are required by your testplan to the /data sub directory.

6. Open a termnal window and cd to the project directory you created (eg. cd /home/username/someproject)

7. Type: ./jmeter-ec2.sh someproject 1
        Where 'someproject' is the name of the project directory (and jmx file) and '1' is the number of instances you wish to spread the test over.
        You may need to run 'chmod u+x jmeter-ec2.sh' if this file does not already have executable permissions.
        You may need to run 'chmod u+x jmeter-ec2.properties' if this file does not already have executable permissions.
        

Notes:
It is not uncommon for an instance to fail to start, this is part of using the Cloud and for that reason this script will dynamically respond to this
    event by adjusting the number of instances that are used for the test. For example, if you request 10 instances but 1 fails then the test will be
    run using only 9 machines. This should not be a problem as the load will still be evenly spread and the end results (the throughput) identical. In a similar
    fashion, should Amazon not provide all the instances you asked for (each accunt is limited) then the script will also adjust to this scenario.
    
Any testplan should always have suitable pacing to regulate throughput. This script distributes load based on threads, it is assumed that these threads
    are setup with suitable timers. If not, adding more hardware could create unpredictable results.



Further details:
  http://www.http503.com/2012/jmeter-ec2/

The source repository is at:
  https://github.com/oliverlloyd/jmeter-ec2