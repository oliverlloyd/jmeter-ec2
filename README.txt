JMeter ec2 Script
-----------------------------

This shell script will allow you to run your local JMeter jmx files using Amazon's EC2 service. It will dynamically install Java and Jmeter, so it
will work over most AMI types, and it will run your test over as many instances as you wish (or are allowed to create by Amazon - the default is 20)
automatically ajusting the test parameters to evenly distribute the load. The script will collate the resultsvfrom each host in real time and display
the output of the Generate Summary Results listener as the test is running (both per individual host and an agregated view across all hosts).
Once execution is complete it will download each hosts jtl file and collate them all together to give one file that can be viewed using the usual
JMeter listeners.

Usage: ./jmeter-ec2 [PROJECT NAME] [NUMBER OF INSTANCES DESIRED]


Pre-requisits
-- An Amazon ec2 account.
-- Amazon API tools must be installed as per Amazon's instructions.
-- Testplans should have a Generate Summary Results Listener present and enabled (no other listeners are required).


Execution Instructions (for Linux based OSs - 32 & 64bit)
1. Create a project directory on your machine. For example: '/home/username/someproject'.
    a) Under the root directory, created three directories named 'jmx', 'resutls' and 'data. For example, like this:
        /home/username/someproject
        INSERT EXAMPLE HERE...

2. Download all files from https://github.com/oliverlloyd/jmeter-ec2.git and place them in /home/username/someproject.

3. Edit the file jmeter-ec2.properties, each value listed below must be set:
    LOCAL_HOME="[Your local project directory, created above, eg. /home/username/someproject]"
        The script needs to know a location remotely where it can read and write data from while it runs.
    REMOTE_HOME="/tmp" # This value can be left as the default unless you have a specific requirement to change it
        This is the location where the script will execute the test from - it is not important as it will only exist for the duration of the test.
    AMI_ID="[A linix based AMI, eg. ami-c787bbb3]"
        This only needs to be a basic AMI, the Amazon examples work fine. Both Java and JMeter are installed by the script and are not required.
        
4. Copy your JMeter jmx file to your project directory and rename it to the same name as the directory. For example, if
   you created the directory'/testing/myproject' then you should name the jmx file 'myproject.jmx'.
   
5. Copy any data files that are required by your testplan to the same project directory.

6. If your testplan has any references to external files such as a CSV file then you will need to update the testplan as follows:
    a) For each reference to an external file, replace the existing reference with '${test.root}/myproject/myfilename.csv'. For example, if you
    had a Filename value of /home/username/someproject/data/myfile.csv you should copy the file to directory created above and replace the value
    in the Filename field with '${test.root}/someproject/myfile.csv'
    b) Create a new User Defined Variable at the root of the testplan called test_root with a value of ${__P(test.root,/home/username/someproject)}
        The test.root property will default to /home/username/someproject but during execution by the jmeter-ec2 shell script it will use the value
        specified by REMOTE_HOME n the jmeter-ec2.properties file. This is useful as it allows you to run the testplan locally and remotely
        without making any edits.
        

7. Steps reuired for the dynamic distribution business.

[The files example.jmx and example.csv are given to demonstrate steps 6 & 7 above.]

8. Open a termnal window and cd to the project directory you created (eg. cd /home/username/someproject)

9. Type './jmeter-ec2 someproject 1'
        Where 'someproject' is the name of the jmx file and '1' is the number of instances you wish to spread the test over.
        You may need to run 'chmod u+x jmeter-ec2.sh' if this file does not already have executable permissions.
        
        
Further details:
  http://www.http503.com/

The source repository is at:
  https://github.com/oliverlloyd/jmeter-ec2.git