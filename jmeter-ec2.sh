#!/bin/bash

PROJECT=$1
INSTANCE_COUNT=$2
DATETIME=$(date "+%s")
LOCAL_HOME="/home/ubuntu"
REMOTE_HOME="/tmp"
AMI_ID="ami-c787bbb3"

cd $EC2_HOME

# create the instance(s) and capture the instance id(s)
echo "launching instance(s)..."
instanceids=$(ec2-run-instances --key olloyd-eu -t m1.small -g jmeter -n 1-$INSTANCE_COUNT --availability-zone \
    eu-west-1b $AMI_ID | awk '/^INSTANCE/ {print $2}')


# wait for each instance to be fully operational
while read instanceid
do
    echo -n "waiting for $instanceid to start running..."
    while host=$(ec2-describe-instances "$instanceid" | egrep ^INSTANCE | cut -f4) && test -z $host; do echo -n .; sleep 1; done
    echo -n "waiting for ssh connection to start..."
    while ssh -n -o StrictHostKeyChecking=no -q -i ~/.ec2/olloyd-eu.pem root@$host true && test; do echo -n .; sleep 1; done
    echo "$host ready"
done <<<"$instanceids"


# get the host names or each instance
hosts=$(ec2-describe-instances --filter "instance-state-name=running"| awk '/'"$AMI_ID"'/ {print $4}')


# Install JAVA JRE & JMeter 2.5.1
while read host
do
    echo -n "preparing $host..."
    # install java
    echo -n "installing java..."
    ssh -n -q -o StrictHostKeyChecking=no -i ~/.ec2/olloyd-eu.pem root@$host "wget -q -O $REMOTE_HOME/jre-6u30-linux-i586-rpm.bin https://s3.amazonaws.com/oliverlloyd/jre-6u30-linux-i586-rpm.bin"
    ssh -n -q -o StrictHostKeyChecking=no -i ~/.ec2/olloyd-eu.pem root@$host "chmod 755 $REMOTE_HOME/jre-6u30-linux-i586-rpm.bin"
    ssh -n -q -o StrictHostKeyChecking=no -i ~/.ec2/olloyd-eu.pem root@$host "$REMOTE_HOME/jre-6u30-linux-i586-rpm.bin >> $REMOTE_DIR/jre-6u30-linux-i586-rpm"
    # install jmeter
    echo -n "installing jmeter..."
    ssh -n -q -o StrictHostKeyChecking=no -i ~/.ec2/olloyd-eu.pem root@$host "wget -q -O $REMOTE_HOME/jakarta-jmeter-2.5.1.tgz https://s3.amazonaws.com/oliverlloyd/jakarta-jmeter-2.5.1.tgz"
    ssh -n -q -o StrictHostKeyChecking=no -i ~/.ec2/olloyd-eu.pem root@$host "tar -C $REMOTE_HOME -xf $REMOTE_HOME/jakarta-jmeter-2.5.1.tgz"
    echo "ready"
done <<< "$hosts"


# scp the test files onto each host  
while read host
do
    echo
    echo "copying files to $host..."
    ssh -n -o StrictHostKeyChecking=no -q -i ~/.ec2/olloyd-eu.pem root@$host mkdir $REMOTE_HOME/$PROJECT
    scp -o StrictHostKeyChecking=no -r -i ~/.ec2/olloyd-eu.pem $LOCAL_HOME/$PROJECT root@$host:$REMOTE_HOME/$PROJECT
    #
    # download a copy of the custom jmeter.properties & jmeter.sh files from GitHub
    #
    # ****** Note. This is only required if the default values are not suitable. *****
    #
    # The files referenced below contain the following amendments from the default:
    # -- jmeter.properties --
    # jmeter.save.saveservice.output_format=csv - more efficient
    # jmeter.save.saveservice.hostname=true - potentially useful in this context but not required
    #
    # -- jmeter.sh --
    # HEAP="-Xms2048m -Xmx2048m" - this is assuming the instance chosen has sufficient memory, more than likely the case
    # NEW="-XX:NewSize=256m -XX:MaxNewSize=256m" - arguably overkill
    # 
    ssh -n -q -o StrictHostKeyChecking=no -i ~/.ec2/olloyd-eu.pem root@$host "wget -q -O $REMOTE_HOME/jakarta-jmeter-2.5.1/bin/jmeter.properties https://github.com/oliverlloyd/jmeter-ec2/blob/master/jmeter.properties"
    ssh -n -q -o StrictHostKeyChecking=no -i ~/.ec2/olloyd-eu.pem root@$host "wget -q -O $REMOTE_HOME/jakarta-jmeter-2.5.1/bin/jmeter.sh https://github.com/oliverlloyd/jmeter-ec2/blob/master/jmeter.sh
    done <<<"$hosts"
echo ""


# run jmeter test plan
counter=0
while read host
do
    echo "running jmeter on $host..."
    (ssh -n -o StrictHostKeyChecking=no -i ~/.ec2/olloyd-eu.pem root@$host \
        $REMOTE_HOME/jakarta-jmeter-2.5.1/bin/jmeter.sh -n -t $REMOTE_HOME/$PROJECT/jmx/$PROJECT.jmx \
        -Jtest.root=$REMOTE_HOME \
        -l $REMOTE_HOME/$PROJECT/$PROJECT-$DATETIME-$counter.jtl \
        > $LOCAL_HOME/$PROJECT/$DATETIME-$host-stdout.out) &
    counter=$((counter+1))
done <<<"$hosts"


# read the results data and print updates to the screen
count_total=0
avg_total=0
count_overallhosts=0
avg_overallhosts=0
i=1
firstmodmatch="TRUE"

# check to see if the test is complete
res=$(grep -c "end of run" $LOCAL_HOME/$PROJECT/$DATETIME*stdout.out | awk -F: '{ s+=$NF } END { print s }')

while [ $res != $INSTANCE_COUNT ]; # test not complete
do
    # gather results data and write to screen for each host
    while read host
    do
        check=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-stdout.out | grep "Results =" | tail -1 | awk '{print $1}') # make sure the test has really started to write results to the file
        if [[ -n "$check" ]] ; then # not null
            if [ $check == "Generate" ] ; then # test has begun
                screenupdate=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-stdout.out | grep "Results +" | tail -1)
                echo "$screenupdate | host: $host" # write results to screen
                # get the latest values
                count=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-stdout.out | grep "Results +" | tail -1 | awk '{print $5}') # pull out the current count
                avg=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-stdout.out | grep "Results +" | tail -1 | awk '{print $11}') # pull out current avg
                #tps=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-stdout.out | grep "Results +" | tail -1 | awk '{print $9}') # pull out current tps
                # get the latest summary values
                count_total=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-stdout.out | grep "Results =" | tail -1 | awk '{print $5}')
                avg_total=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-stdout.out | grep "Results =" | tail -1 | awk '{print $11}')
                if [[ -n "$count_total" ]] ; then # not null (bc bombs on nulls) # redundant if - remove and retest
                    count_overallhosts=$(echo "$count_overallhosts+$count_total" | bc) # add the value from this host to the values from other hosts
                fi
                if [[ -n "$avg_total" ]] ; then # not null # redundant if - remove and retest
                    avg_overallhosts=$(echo "$avg_overallhosts+$avg_total" | bc)
                fi
            fi
        fi
    done <<<"$hosts" # next host
    
    # calculate the average over all hosts
    avg_overallhosts=$(echo "$avg_overallhosts/$INSTANCE_COUNT;" | bc)
    
    # every n loops print a running summary (if each host is running)
    n=3 # could be passed in?
    mod=$(echo "$i % $n"|bc)
    if [ $mod == 0 ] ; then
        if [ $firstmodmatch == "TRUE" ] ; then # don't write summary results the first time (because it's not useful)
            firstmodmatch="FALSE"
        else
            # first check the results files to make sure data is available
            wait=0
            while read host
            do
                result_count=$(grep -c "Results =" $LOCAL_HOME/$PROJECT/$DATETIME-$host-stdout.out)
                if [ $result_count = 0 ] ; then
                    wait=1
                fi
            done <<< "$hosts"
            
            # now write out the data to the screen
            if [ $wait == 0 ] ; then # each file is ready to summarise
                echo ""
                echo "-- Summary --"
                while read host
                do
                    screenupdate=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-stdout.out | grep "Results =" | tail -1)
                    echo "$screenupdate | host: $host" # write results to screen
                done <<< "$hosts"
                echo "RUNNING TOTALS (across all hosts): count: $count_overallhosts, avg.: $avg_overallhosts"
                echo ""
            fi
        fi
    fi
    i=$(( $i + 1))
    
    # this value should be greater than the Generate Summary Results interval
    sleep 16;
    
    # we rely on JM to keep track of overall test totals (via Results =) so we only need keep count of values over multiple instances
    # there's no need for a running total outside of this loop so we reinitialise the vars here.
    count_total=0
    avg_total=0
    count_overallhosts=0
    avg_overallhosts=0
    
    # check to see if the test is complete
    res=$(grep -c "end of run" $LOCAL_HOME/$PROJECT/$DATETIME*stdout.out | awk -F: '{ s+=$NF } END { print s }')
done


# write a final summary to the screen
while read host
do
    count_total=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-stdout.out | grep "Results =" | tail -1 | awk '{print $5}')
    avg_total=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-stdout.out | grep "Results =" | tail -1 | awk '{print $11}')
    count_overallhosts=$(echo "$count_overallhosts+$count_total" | bc) # add the value from this host to the value from other hosts
    avg_overallhosts=$(echo "$avg_overallhosts+$avg_total" | bc)
done <<<"$hosts" # next host
echo
echo "OVERALL RESULTS: count: $count_overallhosts, avg.: $avg_overallhosts"
echo
echo "test finished"
echo


# tidy up working files
rm $LOCAL_HOME/$PROJECT/$DATETIME*stdout.out


# download the results
counter=0
while read host
do
    echo "downloading results from $host..."
    scp -o StrictHostKeyChecking=no -i ~/.ec2/olloyd-eu.pem root@$host:$REMOTE_HOME/$PROJECT/$PROJECT-$DATETIME-$counter.jtl $LOCAL_HOME/$PROJECT/
    counter=$((counter+1))
done <<<"$hosts"
echo ""


# terminate the running instances just created
while read instanceid
do
    echo "terminating instance..."
    ec2-terminate-instances $instanceid    
done <<<"$instanceids"


# process the files into one jtl results file
echo "processing results..."
for (( i=0; i<$INSTANCE_COUNT; i++ ))
do
    cat $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-$i.jtl >> $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-temp.jtl
    rm $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-$i.jtl # removes the individual results from each host - might be useful to some people to keep these files?
done
sort $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-temp.jtl >> $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-complete.jtl
rm $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-temp.jtl
echo ""
echo "complete"