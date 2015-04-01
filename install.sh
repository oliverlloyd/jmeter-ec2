#!/bin/bash
#
# jmeter-ec2 - Install Script (Runs on remote ec2 server)
#

# Source the jmeter-ec2.properties file, establishing these constants.
. /tmp/jmeter-ec2.properties

REMOTE_HOME=$1
INSTALL_JAVA=$2
JMETER_VERSION=$3


function install_jmeter_plugins() {
    wget -q -O $REMOTE_HOME/JMeterPlugins.jar https://s3.amazonaws.com/jmeter-ec2-downloads/JMeterPlugins.jar
    mv $REMOTE_HOME/JMeterPlugins.jar $REMOTE_HOME/$JMETER_VERSION/lib/ext/
}

function install_mysql_driver() {
    wget -q -O $REMOTE_HOME/mysql-connector-java-5.1.16-bin.jar https://s3.amazonaws.com/jmeter-ec2-downloads/mysql-connector-java-5.1.16-bin.jar
    mv $REMOTE_HOME/mysql-connector-java-5.1.16-bin.jar $REMOTE_HOME/$JMETER_VERSION/lib/
}


cd $REMOTE_HOME

if [ $INSTALL_JAVA -eq 1 ] ; then
    # install java
	
	#ubuntu
	sudo apt-get update #update apt-get
	sudo DEBIAN_FRONTEND=noninteractive apt-get -qqy install default-jre
	wait

#    bits=`getconf LONG_BIT`
#    if [ $bits -eq 32 ] ; then
#        wget -q -O $REMOTE_HOME/jre-6u30-linux-i586-rpm.bin https://s3.amazonaws.com/jmeter-ec2-downloads/jre-6u30-linux-i586-rpm.bin
#        chmod 755 $REMOTE_HOME/jre-6u30-linux-i586-rpm.bin
#        $REMOTE_HOME/jre-6u30-linux-i586-rpm.bin
#    else # 64 bit
#        wget -q -O $REMOTE_HOME/jre-6u30-linux-x64-rpm.bin https://s3.amazonaws.com/jmeter-ec2-downloads/jre-6u30-linux-i586-rpm.bin
#        chmod 755 $REMOTE_HOME/jre-6u30-linux-x64-rpm.bin
#        $REMOTE_HOME/jre-6u30-linux-x64-rpm.bin
#    fi

fi

# install jmeter
case "$JMETER_VERSION" in

jakarta-jmeter-2.5.1)
    # JMeter version 2.5.1
    wget -q -O $REMOTE_HOME/$JMETER_VERSION.tgz http://archive.apache.org/dist/jmeter/binaries/$JMETER_VERSION.tgz
    tar -xf $REMOTE_HOME/$JMETER_VERSION.tgz
    # install jmeter-plugins [http://code.google.com/p/jmeter-plugins/]
    install_jmeter_plugins
    # install mysql jdbc driver
	install_mysql_driver
    ;;

apache-jmeter-*)
    # JMeter version 2.x
    wget -q -O $REMOTE_HOME/$JMETER_VERSION.tgz http://archive.apache.org/dist/jmeter/binaries/$JMETER_VERSION.tgz
    tar -xf $REMOTE_HOME/$JMETER_VERSION.tgz
    # install jmeter-plugins [http://code.google.com/p/jmeter-plugins/]
    install_jmeter_plugins
    # install mysql jdbc driver
	install_mysql_driver
    ;;
    
*)
    echo "Please check the value of JMETER_VERSION in the properties file, $JMETER_VERSION is not recognised."
esac

echo "software installed"
