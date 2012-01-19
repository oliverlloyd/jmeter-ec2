JMeter ec2 Script
-----------------------------

This shell script will allow you to run your local JMeter jmx files using Amazon's EC2 service. The script will collate the results
from each host in real time and display an aggregate view of the output of the Generate Summary Results listener. Once execution is complete
it will download each hosts jtl file and collate them all together to give one file that can be viewed using the usual JMeter listeners.

Pre-requisits

1. 


The source repository is at:
  https://github.com/oliverlloyd/jmeter-ec2.git