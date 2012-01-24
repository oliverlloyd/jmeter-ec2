JMeter ec2 Script
-----------------------------

This shell script will allow you to run your local JMeter jmx files using Amazon's EC2 service. It will dynamically install Java and Jmeter, so it
will work over most AMI types, and it will run your test over as many instances as you wish (or are allowed to create by Amazon - the default is 20)
automatically ajusting the test parameters to evenly distribute the load. The script will collate the resultsvfrom each host in real time and display
the output of the Generate Summary Results listener as the test is running (both per individual host and an agregated view across all hosts).
Once execution is complete it will download each hosts jtl file and collate them all together to give one file that can be viewed using the usual
JMeter listeners.

TO DO:
This project is in development. The following features are pending.
-- Dynamic editing of thread counts
-- Changing any CSV file references to work remotely
-- Acepting jmx filename as a parameter (not requiring that it be named the same as the directory)

Usage: ./jmeter-ec2 [PROJECT NAME] [NUMBER OF INSTANCES DESIRED]*

*IMPORTANT: There is a limit imposed by Amazon on how many instances can be run [the default is 20 instances - Oct 2011].


Pre-requisits
-- An Amazon ec2 account.
-- Amazon API tools must be installed as per Amazon's instructions.
-- Testplans should have a Generate Summary Results Listener present and enabled (no other listeners are required).


Execution Instructions (for Linux based OSs - 32 & 64bit)
1. Create a project directory on your machine. For example: '/home/username/someproject'. This is the working dir for the script. Under the directory
    just created, create three sub directories named 'jmx', 'resutls' and 'data.
    
    Detailed steps:
    a) For example, create a root directory like this: mkdir /home/username/someproject
    b) mkdir /home/username/someproject/jmx
    c) mkdir /home/username/someproject/results
    d) mkdir /home/username/someproject/data

2. Download all files from https://github.com/oliverlloyd/jmeter-ec2.git and place them in the root directory (eg. /home/username/someproject).

3. Edit the file jmeter-ec2.properties, each value listed below must be set:
    LOCAL_HOME="[Your local project directory, created above, eg. /home/username/someproject]"
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
        
4. Copy your JMeter jmx file into the /jmx directory under your root project directory (LOCAL_HOME) and rename it to the same name as the directory.
    For example, if you created the directory'/testing/myproject' then you should name the jmx file 'myproject.jmx', if you are using
    LOCAL_HOME=/home/username/someproject then the jmx file should be renamed to 'someproject.jmx'
    
        Note. This naming convention allows the script to work seemlessly over multiple projects (so long as they are all located in the same root) but
            it would not be difficult to edit the jmeter-ec2.sh file to use a specific jmx filename.
   
5. Copy any data files that are required by your testplan to the /data sub directory.

6. If your testplan has any references to external files such as a CSV file then you will need to update the testplan as follows:
    a) For each reference to an external file, replace the existing reference with '${test_root}/myproject/data/myfilename.csv'. For example, if you
    had a Filename value of /home/username/someproject/csvfiles/myfile.csv you should copy the file to the /data directory created above and replace
    the value in the Filename field with '${test_root}/someproject/data/myfile.csv'
    b) Create a new User Defined Variable at the root of the testplan called test_root with a value of ${__P(test.root,/home/username/someproject)}
        
        Note. test.root (Note the use of the '.' not underscore) is passed to the testplan from the command line by the jmeter-ec2 script. The command
            '-Jtest.root=$REMOTE_HOME' tells JMeter to use the value of $REMOTE_HOME (eg. /tmp) for this variable. Then, the test will look for the csv
            file at /tmp/someproject/data/myfile.csv. ${__P(test.root,/home/username/someproject)} also provides a default value, '/home/username/someproject',
            if when the testplan is executed the test.root value is not specified then the default is used instead. This allows the testplan to be run
            locally and remotely without having to edit the testplan.

7. Steps reuired for the dynamic distribution business.

[The files example.jmx and example.csv are given to demonstrate steps 6 & 7 above.]

8. Open a termnal window and cd to the project directory you created (eg. cd /home/username/someproject)

9. Type './jmeter-ec2 someproject 1'
        Where 'someproject' is the name of the project directory and jmx file and '1' is the number of instances you wish to spread the test over.
        You may need to run 'chmod u+x jmeter-ec2.sh' if this file does not already have executable permissions.
        You may need to run 'chmod u+x jmeter-ec2.properties' if this file does not already have executable permissions.
        
        
Further details:
  http://www.http503.com/

The source repository is at:
  https://github.com/oliverlloyd/jmeter-ec2.git