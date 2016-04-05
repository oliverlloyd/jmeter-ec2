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
    wget -q -O $REMOTE_HOME/JMeterPlugins-Extras-1.3.1.jar https://s3.amazonaws.com/jmeter-ec2/JMeterPlugins-Extras-1.3.1.jar
    mv $REMOTE_HOME/JMeterPlugins-Extras-1.3.1.jar $REMOTE_HOME/$JMETER_VERSION/lib/ext/
}

function install_mysql_driver() {
    wget -q -O $REMOTE_HOME/mysql-connector-java-5.1.16-bin.jar https://s3.amazonaws.com/jmeter-ec2/mysql-connector-java-5.1.16-bin.jar
    mv $REMOTE_HOME/mysql-connector-java-5.1.16-bin.jar $REMOTE_HOME/$JMETER_VERSION/lib/
}

function install_java() {
    sudo DEBIAN_FRONTEND=noninteractive apt-get -qqy install openjdk-7-jre
}

function install_jmeter() {
    # ------------------------------------------------
    #      Decide where to download jmeter from
    #
    # Order of preference:
    #   1. S3, if we have a copy of the file
    #   2. Mirror, if the desired version is current
    #   3. Archive, as a backup
    # ------------------------------------------------
    if [ $(curl -sI https://s3.amazonaws.com/jmeter-ec2/$JMETER_VERSION.tgz | grep -c "403 Forbidden") -eq "0" ] ; then
        # We have a copy on S3 so use that
        echo "Downloading jmeter from S3"
        wget -q -O $REMOTE_HOME/$JMETER_VERSION.tgz https://s3.amazonaws.com/jmeter-ec2/$JMETER_VERSION.tgz
    elif [ $(echo $(curl -s 'http://www.apache.org/dist/jmeter/binaries/') | grep -c "$JMETER_VERSION") -gt "0" ] ; then
        # Nothing found on S3 but this is the current version of jmeter so use the preferred mirror to download
        echo "downloading jmeter from a Mirror"
        wget -q -O $REMOTE_HOME/$JMETER_VERSION.tgz "http://www.apache.org/dyn/closer.cgi?filename=jmeter/binaries/$JMETER_VERSION.tgz&action=download"
    else
        # Fall back to the archive server
        echo "Downloading jmeter from Apache Archive"
        wget -q -O $REMOTE_HOME/$JMETER_VERSION.tgz http://archive.apache.org/dist/jmeter/binaries/$JMETER_VERSION.tgz
    fi

    # Untar downloaded file
    tar -xf $REMOTE_HOME/$JMETER_VERSION.tgz
}


cd $REMOTE_HOME

echo "Updating apt-get..."
sudo apt-get -qqy update
echo "Update of apt-get complete"

if [ $INSTALL_JAVA -eq 1 ] ; then
    # install java on ubuntu
    echo "Installing java..."
    install_java
    echo "Java installed"
fi

# install jmeter
echo "Installing jmeter..."
install_jmeter
echo "Jmeter installed"

# install jmeter-plugins [http://code.google.com/p/jmeter-plugins/]
echo "Installing plugins..."
install_jmeter_plugins
echo "Plugins installed"

# install mysql jdbc driver
echo "Installing mysql driver..."
install_mysql_driver
echo "Driver installed"

# Done
echo "software installed"
