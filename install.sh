#!/bin/bash
#
# jmeter-ec2 - Install Script
#

REMOTE_HOME=$1

cd $REMOTE_HOME


# install java
bits=`getconf LONG_BIT`
if [ $bits -eq 32 ] ; then
    wget -q -O $REMOTE_HOME/jre-6u30-linux-i586-rpm.bin https://s3.amazonaws.com/jmeter-ec2/jre-6u30-linux-i586-rpm.bin
    chmod 755 $REMOTE_HOME/jre-6u30-linux-i586-rpm.bin
    $REMOTE_HOME/jre-6u30-linux-i586-rpm.bin
else # 64 bit
    wget -q -O $REMOTE_HOME/jre-6u30-linux-x64-rpm.bin https://s3.amazonaws.com/jmeter-ec2/jre-6u30-linux-i586-rpm.bin
    chmod 755 $REMOTE_HOME/jre-6u30-linux-x64-rpm.bin
    $REMOTE_HOME/jre-6u30-linux-x64-rpm.bin
fi

# install jmeter
wget -q -O $REMOTE_HOME/jakarta-jmeter-2.5.1.tgz http://www.mirrorservice.org/sites/ftp.apache.org//jmeter/binaries/jakarta-jmeter-2.5.1.tgz
tar -xf $REMOTE_HOME/jakarta-jmeter-2.5.1.tgz
echo "software installed"