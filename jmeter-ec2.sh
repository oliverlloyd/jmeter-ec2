#!/bin/bash

PROJECT=$1
INSTANCE_COUNT=$2
DATETIME=$(date "+%s")

. jmeter-ec2.properties

cd $EC2_HOME
echo
echo "   --------------------------------------------------------------------------------"
echo "       jmeter-ec2 Automation Script - Running $PROJECT.jmx over $INSTANCE_COUNT AWS Instance(s)"
echo "   --------------------------------------------------------------------------------"
echo
echo

# create the instance(s) and capture the instance id(s)
echo -n "requesting $INSTANCE_COUNT instance(s)..."
instanceids=$(ec2-run-instances \
            --key $PEM_FILE \
            -t $INSTANCE_TYPE \
            -g $INSTANCE_SECURITYGROUP \
            -n 1-$INSTANCE_COUNT \
            --availability-zone \
            $INSTANCE_AVAILABILITYZONE $AMI_ID \
            | awk '/^INSTANCE/ {print $2}')
# check to see if Amazon returned the desired number of instances as a limit is placed restricting this and we need to handle the case where
# less than the expected number is given wthout failing the test.
countof_instanceids=`echo $instanceids | awk '{ total = total + NF }; END { print total+0 }'`
if [ "$countof_instanceids" = 0 ] ; then
    echo
    echo "Amazon did not supply any instances, exiting"
    echo
    exit
fi
if [ $countof_instanceids != $INSTANCE_COUNT ] ; then
    echo "$countof_instanceids instance(s) were given by Amazon, the test will continue using only these instance(s)."
    INSTANCE_COUNT=$countof_instanceids
else
    echo "success"
fi
echo



# wait for each instance to be fully operational
status_check_count=0
status_check_limit=45
status_check_limit=`echo "$status_check_limit + $countof_instanceids" | bc` # increase wait time based on instance count
echo -n "waiting for instance status checks to pass (this can take several minutes)..."
count_passed=0
while [ "$count_passed" -ne "$INSTANCE_COUNT" ] && [ $status_check_count -lt $status_check_limit ]
do
    echo -n .
    status_check_count=$(( $status_check_count + 1))
    count_passed=$(ec2-describe-instance-status $instanceids | awk '/INSTANCESTATUS/ {print $3}' | grep -c passed)
    sleep 1
done

if [ $status_check_count -lt $status_check_limit ] ; then # all hosts started ok because count_passed==INSTANCE_COUNT
    # get hostname and build the list used later in the script
    hosts=(`ec2-describe-instances $instanceids | awk '/INSTANCE/ {print $4}'`)
    echo "all hosts ready"
else # Amazon probably failed to start a host [*** NOTE this is fairly common ***] so show a msg - TO DO. Could try to replace it with a new one?
    original_count=$countof_instanceids
    # weirdly, at this stage instanceids develops some newline chars at the end. So we strip them
    instanceids_clean=`echo $instanceids | tr '\n' ' '`
    # filter requested instances for only those that started well
    healthy_instanceids=`ec2-describe-instance-status $instanceids \
                        --filter instance-status.reachability=passed \
                        --filter system-status.reachability=passed \
                        | awk '/INSTANCE\t/ {print $2}'`
    if [ -z "$healthy_instanceids" ] ; then
        countof_instanceids=0
        echo "no instances successfully initialised, exiting"
        exit
    else
        countof_instanceids=`echo $healthy_instanceids | awk '{ total = total + NF }; END { print total+0 }'`
    fi
    countof_failedinstances=`echo "$original_count - $countof_instanceids"|bc`
    if [ "$countof_failedinstances" -gt 0 ] ; then # if we still see failed instances then write a message
        echo "$countof_failedinstances instances(s) failed to start, only $countof_instanceids machine(s) will be used in the test"
        INSTANCE_COUNT=$countof_instanceids
    fi
    hosts=(`ec2-describe-instances $healthy_instanceids | awk '/INSTANCE/ {print $4}'`)
fi
echo



# scp install.sh
echo -n "copying install.sh to $INSTANCE_COUNT server(s)..."
for host in ${hosts[@]} ; do
    (scp -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
                                  -i $PEM_PATH/$PEM_FILE.pem \
                                  $LOCAL_HOME/$PROJECT/install.sh \
                                  $USER@$host:$REMOTE_HOME \
                                  && echo "done" > $LOCAL_HOME/$PROJECT/$DATETIME-$host-scpinstall.out)
done

# check to see if the scp call is complete
# (could just use the wait command here...)
res=0
while [ "$res" != "$INSTANCE_COUNT" ] ;
do
    echo -n .
    res=$(grep -c "done" $LOCAL_HOME/$PROJECT/$DATETIME*scpinstall.out \
        | awk -F: '{ s+=$NF } END { print s }') # the awk command here sums up the output if multiple matches were found
    sleep 3
done
echo "complete"
echo



# Install JAVA JRE & JMeter 2.5.1
echo -n "running install.sh on $INSTANCE_COUNT server(s)..."
for host in ${hosts[@]} ; do
    (ssh -nq -o StrictHostKeyChecking=no \
        -i $PEM_PATH/$PEM_FILE.pem $USER@$host \
        "$REMOTE_HOME/install.sh $REMOTE_HOME" \
        > $LOCAL_HOME/$PROJECT/$DATETIME-$host-install.out) &
done

# check to see if the install scripts are complete
res=0
while [ "$res" != "$INSTANCE_COUNT" ] ; do # Installation not complete (count of matches for 'software installed' not equal to count of hosts running the test)
    echo -n .
    res=$(grep -c "software installed" $LOCAL_HOME/$PROJECT/$DATETIME*install.out \
        | awk -F: '{ s+=$NF } END { print s }') # the awk command here sums up the output if multiple matches were found
    sleep 3
done
echo "complete"
echo



# Create a working jmx file and edit it to adjust thread counts and filepaths
cp $LOCAL_HOME/$PROJECT/jmx/$PROJECT.jmx $LOCAL_HOME/$PROJECT/working
working_jmx="$LOCAL_HOME/$PROJECT/working"
temp_jmx="$LOCAL_HOME/$PROJECT/temp"

# first filepaths (this will help with things like csv files)
# edit any 'stringProp filename=' references to use REMOTE_DIR
# we assume that the required dat file is copied into the local /data directory
filepaths=$(awk 'BEGIN { FS = ">" } ; /<stringProp name=\"filename\">[^<]*<\/stringProp>/ {print $2}' $working_jmx | cut -d'<' -f1) # pull out filepath
i=1
while read filepath ; do
    if [ -n "$filepath" ] ; then # this entry is blank so skip it
        # extract the filename from the filepath using the property FILEPATH_SEPARATOR
        # TO DO: This code currently will not replace filenames or paths that have '${}' in them.
        filename=$( echo $filepath | awk -F"$FILEPATH_SEPARATOR" '{print $NF}' )
        endresult="$REMOTE_HOME""$FILEPATH_SEPARATOR""$filename"
        awk '/<stringProp name=\"filename\">[^<]*<\/stringProp>/{c++;if(c=='"$i"') \
                               {sub("filename\">'"$filepath"'<","filename\">'"$endresult"'<")}}1' \
                               $working_jmx > $temp_jmx
        rm $working_jmx
        mv $temp_jmx $working_jmx
    fi
    # increment i
    i=$((i+1))
done <<<"$filepaths"

# now we use the same working file to edit thread counts
# to cope with the problem of trying to spread 10 threads over 3 hosts (10/3 = has a remainder) the script creates a unique jmx for each host
# and then passes out threads to them on a round robin basis
# as part of this we begin here by creating a working jmx file for each separate host using _$y to isolate
for y in "${!hosts[@]}" ; do
    # for each host create a working copy of the jmx file (leave the original intact!)
    cp "$working_jmx" "$working_jmx"_"$y"   
done
# now, if we have multiple hosts, we loop through each threadgroup and then use a nested loop within that to edit the file for each host
if [ "$countof_instanceids" -gt 1 ] ; then # otherwise there's no point adjusting thread counts for a test run on a single instance
    # pull out the current values for each thread group
    threadgroup_threadcounts=$(awk 'BEGIN { FS = ">" } ; /ThreadGroup\.num_threads\">[^<]*</ {print $2}' $working_jmx | cut -d'<' -f1) # put the current thread counts into variable
    threadgroup_names=$(awk 'BEGIN { FS = "\"" } ; /ThreadGroup\" testname=\"[^\"]*\"/ {print $6}' $working_jmx) # capture each thread group name
    
    # get count of thread groups, show results to screen
    countofthreadgroups=`echo $threadgroup_threadcounts | awk '{ total = total + NF }; END { print total+0 }'`
    echo "editing thread counts - $PROJECT.jmx has $countofthreadgroups threadgroup(s):"
        
    i=1
    # now we loop through each thread group, editing a separate file for each host each iteration (nested loop)
    for currentthreadcount in $threadgroup_threadcounts ; do
            # using modulo we distribute the threads over all hosts
            # taking 10(threads)/3(hosts) as an example you would expect two hosts to be given 3 threads and one to be given 4.
            for (( x=1; x<=$currentthreadcount; x++ )); do
                : $(( threads[$(( $x % ${#hosts[@]} ))]++ ))
            done
            
            # here we loop through every host, editing the jmx file and using a temp file to carry the changes over
            for y in "${!hosts[@]}" ; do
                # we're already in a loop for each thread group but awk will parse the entire file each time it is called so we need to
                # use an index to know when to make the edit
                # when c (awk's index) matches i (the for loop's index) then a substitution is made
                awk '/ThreadGroup\.num_threads\">[^<]*</{c++;if(c=='"$i"'){sub("threads\">'"$currentthreadcount"'<","threads\">'"${threads[$y]}"'<")}}1' "$working_jmx"_"$y" > "$temp_jmx"_"$y"
            
                # using awk requires the use of a temp file to save the results of the command, update the working file with this file
                rm "$working_jmx"_"$y"
                mv "$temp_jmx"_"$y" "$working_jmx"_"$y"
            done
            
            # get the thread group name
            z=1
            for row in $threadgroup_names ; do
                if [ "$z" -eq "$i" ] ; then
                    threadgroupname=$row
                fi
                # increment x
                z=$((z+1))
            done
            
            # write update to screen
            echo "...$i) $threadgroupname has $currentthreadcount thread(s), to be distributed over $INSTANCE_COUNT instance(s)"
            
            # increment i
            i=$((i+1))
            
            unset threads
    done
    echo
fi



# scp the test files onto each host
echo -n "copying test files to $INSTANCE_COUNT server(s)..."
# create $PROJECT dir
echo -n "$PROJECT dir.."
for host in ${hosts[@]} ; do
    (ssh -n -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
                                     -i $PEM_PATH/$PEM_FILE.pem \
                                     $USER@$host mkdir \
                                     $REMOTE_HOME/$PROJECT) &
done
wait
echo -n "done...."

# scp jmx dir
echo -n "jmx files.."
for y in "${!hosts[@]}" ; do
    (scp -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r \
                                  -i $PEM_PATH/$PEM_FILE.pem \
                                  $LOCAL_HOME/$PROJECT/working_$y \
                                  $USER@${hosts[$y]}:$REMOTE_HOME/$PROJECT/execute.jmx) &
done
wait
echo -n "done...."

# scp data dir
echo -n "data dir.."
if [ -x $LOCAL_HOME/$PROJECT/data ] ; then # don't try to upload this optional dir if it is not present
    for host in ${hosts[@]} ; do
        (scp -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r \
                                      -i $PEM_PATH/$PEM_FILE.pem \
                                      $LOCAL_HOME/$PROJECT/data \
                                      $USER@$host:$REMOTE_HOME/$PROJECT) &
    done
    wait
    echo -n "done...."
fi

# scp jmeter.properties
echo -n "jmeter.properties.."
for host in ${hosts[@]} ; do
    (scp -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
                                  -i $PEM_PATH/$PEM_FILE.pem \
                                  $LOCAL_HOME/jmeter.properties \
                                  $USER@$host:$REMOTE_HOME/jakarta-jmeter-2.5.1/bin/) &
done
wait
echo -n "done...."

# scp jmeter execution file
echo -n "jmeter execution file..."
for host in ${hosts[@]} ; do
    (scp -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
                                  -i $PEM_PATH/$PEM_FILE.pem \
                                  $LOCAL_HOME/jmeter \
                                  $USER@$host:$REMOTE_HOME/jakarta-jmeter-2.5.1/bin/) &
done
wait
echo "all files uploaded"
echo




#
# run jmeter test plan
#
#    ssh -nq -o UserKnownHostsFile=/dev/null \
#         -o StrictHostKeyChecking=no \
#        -i $PEM_PATH/$PEM_FILE.pem $USER@$host \             # ec2 key file
#        $REMOTE_HOME/jakarta-jmeter-2.5.1/bin/jmeter.sh -n \ # execute jmeter - non GUI - from where it was just installed
#        -t $REMOTE_HOME/$PROJECT/execute.jmx \           # run the jmx file that was uploaded
#        -Jtest.root=$REMOTE_HOME \                           # pass in the root directory used to run the test to the testplan - used if external data files are present
#        -Jtest.instances=$INSTANCE_COUNT \                   # pass in to the test how many instances are being used
#        -l $REMOTE_HOME/$PROJECT-$DATETIME-$counter.jtl \    # write results to the root of remote home
#        > $LOCAL_HOME/$PROJECT/$DATETIME-$host-jmeter.out    # redirect the output from Generate Summary Results to a local temp file (later read to present real time results to screen)
#
# TO DO: Temp files are a poor way to track multiple subshells - improve?
#
echo
echo "starting jmeter on:"
for host in ${hosts[@]} ; do
    echo $host
done
counter=0
for host in ${hosts[@]} ; do
    ( ssh -nq -o StrictHostKeyChecking=no \
    -i $PEM_PATH/$PEM_FILE.pem $USER@$host \
    $REMOTE_HOME/jakarta-jmeter-2.5.1/bin/jmeter.sh -n \
    -t $REMOTE_HOME/$PROJECT/execute.jmx \
    -Jtest.root=$REMOTE_HOME \
    -Jtest.instances=$INSTANCE_COUNT \
    -l $REMOTE_HOME/$PROJECT-$DATETIME-$counter.jtl \
    > $LOCAL_HOME/$PROJECT/$DATETIME-$host-jmeter.out ) &
    counter=$((counter+1))
done
#done <<<"${hosts_str}"
echo
echo

echo "========================================================= START OF JMETER-EC2 TEST ================================================================================"
echo "Test started at $(date)"
# read the results data and print updates to the screen
echo "waiting for output..."
echo
# TO DO: Are thse required?
count_total=0
avg_total=0
count_overallhosts=0
avg_overallhosts=0
tps_overallhosts=0
errors_overallhosts=0

i=1
firstmodmatch="TRUE"
res=0
while [ $res != $INSTANCE_COUNT ] ; do # test not complete (count of matches for 'end of run' not equal to count of hosts running the test)
    # gather results data and write to screen for each host
    #while read host ; do
    for host in ${hosts[@]} ; do
        check=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $1}') # make sure the test has really started to write results to the file
        if [[ -n "$check" ]] ; then # not null
            if [ $check == "Generate" ] ; then # test has begun
                screenupdate=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-jmeter.out | grep "Results +" | tail -1)
                echo "$screenupdate | host: $host" # write results to screen
                
                # get the latest values
                count=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-jmeter.out | grep "Results +" | tail -1 | awk '{print $5}') # pull out the current count
                avg=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-jmeter.out | grep "Results +" | tail -1 | awk '{print $11}') # pull out current avg
                tps_raw=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-jmeter.out | grep "Results +" | tail -1 | awk '{print $9}') # pull out current tps
                errors_raw=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-jmeter.out | grep "Results +" | tail -1 | awk '{print $17}') # pull out current errors
                tps=${tps_raw%/s} # remove the trailing '/s'
                
                # get the latest summary values
                count_total=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $5}')
                avg_total=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $11}')
                tps_total_raw=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $9}')
                tps_total=${tps_total_raw%/s} # remove the trailing '/s'
                errors_total=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $17}')
                
                count_overallhosts=$(echo "$count_overallhosts+$count_total" | bc) # add the value from this host to the values from other hosts
                avg_overallhosts=$(echo "$avg_overallhosts+$avg" | bc)
                tps_overallhosts=$(echo "$tps_overallhosts+$tps" | bc) 
                errors_overallhosts=$(echo "$errors_overallhosts+$errors_total" | bc) # add the value from this host to the values from other hosts
            fi
        fi
    done #<<<"${hosts_str}" # next host
    
    # calculate the average respone time over all hosts
    avg_overallhosts=$(echo "$avg_overallhosts/$INSTANCE_COUNT" | bc)
    
    # every n loops print a running summary (if each host is running)
    n=3 # could be passed in?
    mod=$(echo "$i % $n"|bc)
    if [ $mod == 0 ] ; then
        if [ $firstmodmatch == "TRUE" ] ; then # don't write summary results the first time (because it's not useful)
            firstmodmatch="FALSE"
        else
            # first check the results files to make sure data is available
            wait=0
            #while read host ; do
            for host in ${hosts[@]} ; do
                result_count=$(grep -c "Results =" $LOCAL_HOME/$PROJECT/$DATETIME-$host-jmeter.out)
                if [ $result_count = 0 ] ; then
                    wait=1
                fi
            done #<<<"${hosts_str}" # next host
            
            # now write out the data to the screen
            if [ $wait == 0 ] ; then # each file is ready to summarise
                echo ""
                #while read host ; do
                for host in ${hosts[@]} ; do
                    screenupdate=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1)
                    echo "$screenupdate | host: $host" # write results to screen
                done #<<<"${hosts_str}" # next host
                echo
                echo "$(date) [RUNNING TOTALS]: count: $count_overallhosts, avg: $avg_overallhosts (ms), tps: $tps_overallhosts (p/sec), errors: $errors_overallhosts"
                echo
            fi
        fi
    fi
    i=$(( $i + 1))
    
    # this value should be greater than the Generate Summary Results interval set in jmeter.properties (summariser.interval=15)
    sleep 16;
    
    # we rely on JM to keep track of overall test totals (via Results =) so we only need keep count of values over multiple instances
    # there's no need for a running total outside of this loop so we reinitialise the vars here.
    count_total=0
    avg_total=0
    count_overallhosts=0
    avg_overallhosts=0
    tps_overallhosts=0
    errors_overallhosts=0
    
    # check again to see if the test is complete (inside the loop)
    res=$(grep -c "end of run" $LOCAL_HOME/$PROJECT/$DATETIME*jmeter.out | awk -F: '{ s+=$NF } END { print s }')
done
# test complete


# now the test is complete calculate a final summary and write to the screen
#while read host ; do
for host in ${hosts[@]} ; do
    # get the final summary values
    count_total=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $5}')
    avg_total=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $11}')
    tps_total_raw=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $9}')
    tps_total=${tps_total_raw%/s} # remove the trailing '/s'
    errors_total=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $17}')
    
    # running totals
    count_overallhosts=$(echo "$count_overallhosts+$count_total" | bc) # add the value from this host to the values from other hosts
    avg_overallhosts=$(echo "$avg_overallhosts+$avg_total" | bc)
    tps_overallhosts=$(echo "$tps_overallhosts+$tps_total" | bc) # add the value from this host to the values from other hosts
    errors_overallhosts=$(echo "$errors_overallhosts+$errors_total" | bc) # add the value from this host to the values from other hosts
done #<<<"${hosts_str}" # next host

# calculate averages over all hosts
avg_overallhosts=$(echo "$avg_overallhosts/$INSTANCE_COUNT" | bc)

# display final results
echo
echo
echo "$(date) [OVERALL RESULTS]: count: $count_overallhosts, avg: $avg_overallhosts (ms), tps: $tps_overallhosts (p/sec), errors: $errors_overallhosts"
echo
echo "========================================================= END OF JMETER-EC2 TEST =================================================================================="
echo
echo



# tidy up working files
# for debugging purposes you could comment out these lines
rm $LOCAL_HOME/$PROJECT/$DATETIME*.out
rm $LOCAL_HOME/$PROJECT/working* 



# download the results
counter=0
#while read host ; do
for host in ${hosts[@]} ; do
    echo -n "downloading results from $host..."
    scp -q -o UserKnownHostsFile=/dev/null \
                                 -o StrictHostKeyChecking=no \
                                 -i $PEM_PATH/$PEM_FILE.pem \
                                 $USER@$host:$REMOTE_HOME/$PROJECT-$DATETIME-$counter.jtl \
                                 $LOCAL_HOME/$PROJECT/
    counter=$((counter+1))
    echo "$LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-$counter.jtl complete"
done #<<<"${hosts_str}" # next host
echo



# terminate the running instances just created
echo "terminating instance(s)..."
ec2-terminate-instances $instanceids
echo



# process the files into one jtl results file
echo -n "processing results..."
for (( i=0; i<$INSTANCE_COUNT; i++ )) ; do
    cat $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-$i.jtl >> $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-temp.jtl
    rm $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-$i.jtl # removes the individual results files (from each host) - might be useful to some people to keep these files?
done
sort $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-temp.jtl >> $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-complete.jtl
rm $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-temp.jtl
mkdir -p $LOCAL_HOME/$PROJECT/results/
mv $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-complete.jtl $LOCAL_HOME/$PROJECT/results/
echo "complete"
echo
echo
echo "   --------------------------------------------------------------------------------"
echo "                  jmeter-ec2 Automation Script - COMPLETE"
echo
echo "   Test Results: $LOCAL_HOME/$PROJECT/results/$PROJECT-$DATETIME-complete.jtl"
echo "   --------------------------------------------------------------------------------"
echo