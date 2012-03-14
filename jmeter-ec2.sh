#!/bin/bash

PROJECT=$1
INSTANCE_COUNT=$2
DATETIME=$(date "+%s")

. jmeter-ec2.properties

cd $EC2_HOME

# check project directry exists
if [ ! -d "$LOCAL_HOME/$PROJECT" ] ; then
    echo "The directory $LOCAL_HOME/$PROJECT does not exist."
    echo
    echo "Script exiting."
    exit
fi

function runsetup() {
    # if REMOTE_HOSTS is not set then no hosts have been specified to run the test on so we will request them from Amazon
    if [ -z "$REMOTE_HOSTS" ] ; then
        
        # check if ELASTIC_IPS is set, if it is we need to make sure we have enough of them
        if [ ! -z "$ELASTIC_IPS" ] ; then # Not Null - same as -n
            elasticips=(`echo $ELASTIC_IPS | tr "," "\n" | tr -d ' '`)
            elasticips_count=${#elasticips[@]}
            if [ "$INSTANCE_COUNT" -gt "$elasticips_count" ] ; then
                echo
                echo "You are trying to launch $INSTANCE_COUNT instance but you have only specified $elasticips_count elastic IPs."
                echo "If you wish to use Staitc IPs for each test instance then you must increase the list of values given for ELASTIC_IPS in the properties file."
                echo
                echo "Alternatively, if you set the STATIC_IPS property to \"\" or do not specify it at all then the test will run without trying to assign static IPs."
                echo
                echo "Script exiting..."
                echo
                exit
            fi
        fi
        echo
        echo "   -------------------------------------------------------------------------------------"
        echo "       jmeter-ec2 Automation Script - Running $PROJECT.jmx over $INSTANCE_COUNT AWS Instance(s)"
        echo "   -------------------------------------------------------------------------------------"
        echo
        echo
        
        # default to 1 instance if a count is not specified
        if [ -z "$INSTANCE_COUNT" ] ; then INSTANCE_COUNT=1; fi
        
        # create the instance(s) and capture the instance id(s)
        echo -n "requesting $INSTANCE_COUNT instance(s)..."
        instanceids=(`ec2-run-instances \
                    --key $PEM_FILE \
                    -t $INSTANCE_TYPE \
                    -g $INSTANCE_SECURITYGROUP \
                    -n 1-$INSTANCE_COUNT \
                    --availability-zone \
                    $INSTANCE_AVAILABILITYZONE $AMI_ID \
                    | awk '/^INSTANCE/ {print $2}'`)
        
        # check to see if Amazon returned the desired number of instances as a limit is placed restricting this and we need to handle the case where
        # less than the expected number is given wthout failing the test.
        countof_instanceids=${#instanceids[@]}
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
            count_passed=$(ec2-describe-instance-status ${instanceids[@]} | awk '/INSTANCESTATUS/ {print $3}' | grep -c passed)
            sleep 1
        done
        
        if [ $status_check_count -lt $status_check_limit ] ; then # all hosts started ok because count_passed==INSTANCE_COUNT
            # get hostname and build the list used later in the script
            hosts=(`ec2-describe-instances ${instanceids[@]} | awk '/INSTANCE/ {print $4}'`)
            echo "all hosts ready"
        else # Amazon probably failed to start a host [*** NOTE this is fairly common ***] so show a msg - TO DO. Could try to replace it with a new one?
            original_count=$countof_instanceids
            # weirdly, at this stage instanceids develops some newline chars at the end. So we strip them
            #instanceids_clean=`echo $instanceids | tr '\n' ' '`
            # filter requested instances for only those that started well
            healthy_instanceids=(`ec2-describe-instance-status ${instanceids[@]} \
                                --filter instance-status.reachability=passed \
                                --filter system-status.reachability=passed \
                                | awk '/INSTANCE\t/ {print $2}'`)
            if [ "${#healthy_instanceids[@]}" -eq 0 ] ; then
                countof_instanceids=0
                echo "no instances successfully initialised, exiting"
                exit
            else
                countof_instanceids=${#healthy_instanceids[@]}
            fi
            countof_failedinstances=`echo "$original_count - $countof_instanceids"|bc`
            if [ "$countof_failedinstances" -gt 0 ] ; then # if we still see failed instances then write a message
                echo "$countof_failedinstances instances(s) failed to start, only $countof_instanceids machine(s) will be used in the test"
                INSTANCE_COUNT=$countof_instanceids
            fi
            hosts=(`ec2-describe-instances $healthy_instanceids | awk '/INSTANCE/ {print $4}'`)
            instanceids=$healthy_instanceids
        fi
        echo
        
        # if provided, assign elastic IPs to each instance
        if [ ! -z "$ELASTIC_IPS" ] ; then # Not Null - same as -n
            echo "assigning elastic ips..."
            for x in "${!instanceids[@]}" ; do
                ec2-associate-address ${elasticips[x]} -i ${instanceids[x]}
                hosts[x]=${elasticips[x]}
                # check for ssh connectivity on the new address
                while ssh -o StrictHostKeyChecking=no -q -i $PEM_PATH/$PEM_FILE.pem \
                    $USER@${hosts[x]} true && test; \
                    do echo -n .; sleep 1; done
                # Note. If any IP is already in use on an instance that is still running then the ssh check above will return
                # a false positive. If this scenario is common you should put a sleep statement here.
            done
            echo "complete"
            echo
        fi
        
        # Tell install.sh to attempt to install JAVA
        attemptjavainstall=1
    else # the property REMOTE_HOSTS is set so we wil use this list of predefined hosts instead
        hosts=(`echo $REMOTE_HOSTS | tr "," "\n" | tr -d ' '`)
        INSTANCE_COUNT=${#hosts[@]}
        # Tell install.sh to not attempt to install JAVA
        attemptjavainstall=0
        echo
        echo "   -------------------------------------------------------------------------------------"
        echo "       jmeter-ec2 Automation Script - Running $PROJECT.jmx over $INSTANCE_COUNT predefined host(s)"
        echo "   -------------------------------------------------------------------------------------"
        echo
        echo
    
	    # Check if remote hosts are up
	    for host in ${hosts[@]} ; do
	        if [ ! "$(ssh -q -q \
	            -o StrictHostKeyChecking=no \
	            -o "BatchMode=yes" \
	            -o "ConnectTimeout 15" \
	            -i $PEM_PATH/$PEM_FILE.pem \
	            $USER@$host echo up 2>&1)" == "up" ] ; then
	            echo "Host $host is not responding, script exiting..."
	            echo
	            exit
	        fi
	    done
    fi

    # scp install.sh
    echo -n "copying install.sh to $INSTANCE_COUNT server(s)..."
    for host in ${hosts[@]} ; do
        (scp -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
                                      -i $PEM_PATH/$PEM_FILE.pem \
                                      $LOCAL_HOME/install.sh \
                                      $USER@$host:$REMOTE_HOME \
                                      && echo "done" > $LOCAL_HOME/$PROJECT/$DATETIME-$host-scpinstall.out)
    done
    
    # check to see if the scp call is complete (could just use the wait command here...)
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
    
    # Install test software
    echo -n "running install.sh on $INSTANCE_COUNT server(s)..."
    for host in ${hosts[@]} ; do
        (ssh -nq -o StrictHostKeyChecking=no \
            -i $PEM_PATH/$PEM_FILE.pem $USER@$host \
            "$REMOTE_HOME/install.sh $REMOTE_HOME $attemptjavainstall $JMETER_VERSION"\
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
    
    
    # Create a working jmx file and edit it to adjust thread counts and filepaths (leave the original jmx intact!)
    cp $LOCAL_HOME/$PROJECT/jmx/$PROJECT.jmx $LOCAL_HOME/$PROJECT/working
    working_jmx="$LOCAL_HOME/$PROJECT/working"
    temp_jmx="$LOCAL_HOME/$PROJECT/temp"
    
    # first filepaths (this will help with things like csv files)
    # edit any 'stringProp filename=' references to use $REMOTE_DIR in place of whatever local path was being used
    # we assume that the required dat file is copied into the local /data directory
    filepaths=$(awk 'BEGIN { FS = ">" } ; /<stringProp name=\"filename\">[^<]*<\/stringProp>/ {print $2}' $working_jmx | cut -d'<' -f1) # pull out filepath
    i=1
    while read filepath ; do
        if [ -n "$filepath" ] ; then # this entry is not blank
            # extract the filename from the filepath using '/' separator
            filename=$( echo $filepath | awk -F"/" '{print $NF}' )
            endresult="$REMOTE_HOME"/data/"$filename"
            if [[ $filepath =~ .*\$.* ]] ; then
                echo "The path $filepath contains a $ char, this currently fails the awk sub command."
                echo "Until I get around to fixing this, you'll have to remove these from all filepaths. Sorry."
                echo
                echo "Script exiting"
                exit
            fi
            awk '/<stringProp name=\"filename\">[^<]*<\/stringProp>/{c++;if(c=='"$i"') \
                                   {sub("filename\">'"$filepath"'<","filename\">'"$endresult"'<")}}1'  \
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
        # for each host create a working copy of the jmx file
        cp "$working_jmx" "$working_jmx"_"$y"   
    done
    # now, if we have multiple hosts, we loop through each threadgroup and then use a nested loop within that to edit the file for each host
    if [ "$INSTANCE_COUNT" -gt 1 ] ; then # otherwise there's no point adjusting thread counts for a test run on a single instance
        # pull out the current values for each thread group
        threadgroup_threadcounts=(`awk 'BEGIN { FS = ">" } ; /ThreadGroup\.num_threads\">[^<]*</ {print $2}' $working_jmx | cut -d'<' -f1`) # put the current thread counts into variable
        threadgroup_names=(`awk 'BEGIN { FS = "\"" } ; /ThreadGroup\" testname=\"[^\"]*\"/ {print $6}' $working_jmx`) # capture each thread group name
        
        # first we check to make sure each threadgroup_threadcounts is numeric
        for n in ${!threadgroup_threadcounts[@]} ; do
            case ${threadgroup_threadcounts[$n]} in
                ''|*[!0-9]*)
                    echo "Error: Thread Group: ${threadgroup_names[$n]} has the value: ${threadgroup_threadcounts[$n]}, which is not numeric - Thread Count must be numeric!"
                    echo
                    echo "Script exiting..."
                    echo
                    exit;;
                    *);;
            esac
        done
        
        # get count of thread groups, show results to screen
        countofthreadgroups=${#threadgroup_threadcounts[@]}
        echo "editing thread counts - $PROJECT.jmx has $countofthreadgroups threadgroup(s):"
            
        # now we loop through each thread group, editing a separate file for each host each iteration (nested loop)
        for i in ${!threadgroup_threadcounts[@]} ; do
                # using modulo we distribute the threads over all hosts, building the array 'threads'
                # taking 10(threads)/3(hosts) as an example you would expect two hosts to be given 3 threads and one to be given 4.
                for (( x=1; x<=${threadgroup_threadcounts[$i]}; x++ )); do
                    : $(( threads[$(( $x % ${#hosts[@]} ))]++ ))
                done
                
                # here we loop through every host, editing the jmx file and using a temp file to carry the changes over
                for y in "${!hosts[@]}" ; do
                    # we're already in a loop for each thread group but awk will parse the entire file each time it is called so we need to
                    # use an index to know when to make the edit
                    # when c (awk's index) matches i (the main for loop's index) then a substitution is made
                    findstr="threads\">"${threadgroup_threadcounts[$i]}
                    replacestr="threads\">"${threads[$y]}
                    awk -v "findthis=$findstr" -v "replacewiththis=$replacestr" \
                                     'BEGIN{c=0} \
                                     /ThreadGroup\.num_threads\">[^<]*</ \
                                     {if(c=='"$i"'){sub(findthis,replacewiththis)};c++}1' \
                                     "$working_jmx"_"$y" > "$temp_jmx"_"$y"
    
                    # using awk requires the use of a temp file to save the results of the command, update the working file with this file
                    rm "$working_jmx"_"$y"
                    mv "$temp_jmx"_"$y" "$working_jmx"_"$y"
                done
                
                # write update to screen
                echo "...$i) ${threadgroup_names[$i]} has ${threadgroup_threadcounts[$i]} thread(s), to be distributed over $INSTANCE_COUNT instance(s)"
                
                unset threads
        done
        echo
    fi
    
    
    # scp the test files onto each host
    echo -n "copying test files to $INSTANCE_COUNT server(s)..."
    
    # scp jmx dir
    echo -n "jmx files.."
    for y in "${!hosts[@]}" ; do
        (scp -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r \
                                      -i $PEM_PATH/$PEM_FILE.pem \
                                      $LOCAL_HOME/$PROJECT/working_$y \
                                      $USER@${hosts[$y]}:$REMOTE_HOME/execute.jmx) &
    done
    wait
    echo -n "done...."
    
    # scp data dir
    if [ -r $LOCAL_HOME/$PROJECT/data ] ; then # don't try to upload this optional dir if it is not present
        echo -n "data dir.."
        for host in ${hosts[@]} ; do
            (scp -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r \
                                          -i $PEM_PATH/$PEM_FILE.pem \
                                          $LOCAL_HOME/$PROJECT/data \
                                          $USER@$host:$REMOTE_HOME/) &
        done
        wait
        echo -n "done...."
    fi
    
    # scp jmeter.properties
    if [ -r $LOCAL_HOME/jmeter.properties ] ; then # don't try to upload this optional file if it is not present
        echo -n "jmeter.properties.."
        for host in ${hosts[@]} ; do
            (scp -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
                                          -i $PEM_PATH/$PEM_FILE.pem \
                                          $LOCAL_HOME/jmeter.properties \
                                          $USER@$host:$REMOTE_HOME/$JMETER_VERSION/bin/) &
        done
        wait
        echo -n "done...."
    fi
    
    # scp jmeter execution file
    if [ -r $LOCAL_HOME/jmeter ] ; then # don't try to upload this optional file if it is not present
        echo -n "jmeter execution file..."
        for host in ${hosts[@]} ; do
            (scp -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
                                          -i $PEM_PATH/$PEM_FILE.pem \
                                          $LOCAL_HOME/jmeter \
                                          $USER@$host:$REMOTE_HOME/$JMETER_VERSION/bin/) &
        done
        wait
        echo "all files uploaded"
    fi
    echo
    
    
    
    # run jmeter test plan
    echo "starting jmeter on:"
    for host in ${hosts[@]} ; do
        echo $host
    done
    #
    #    ssh -nq -o UserKnownHostsFile=/dev/null \
    #         -o StrictHostKeyChecking=no \
    #        -i $PEM_PATH/$PEM_FILE.pem $USER@${host[$counter]} \               # ec2 key file
    #        $REMOTE_HOME/$JMETER_VERSION/bin/jmeter.sh -n \               # execute jmeter - non GUI - from where it was just installed
    #        -t $REMOTE_HOME/execute.jmx \                                      # run the jmx file that was uploaded
    #        -l $REMOTE_HOME/$PROJECT-$DATETIME-$counter.jtl \                  # write results to the root of remote home
    #        > $LOCAL_HOME/$PROJECT/$DATETIME-${host[$counter]}-jmeter.out      # redirect output from Generate Summary Results to a local temp file (read to present real time results to screen)
    #
    # TO DO: Temp files are a poor way to track multiple subshells - improve?
    #
    for counter in ${!hosts[@]} ; do
        ( ssh -nq -o StrictHostKeyChecking=no \
        -i $PEM_PATH/$PEM_FILE.pem $USER@${hosts[$counter]} \
        $REMOTE_HOME/$JMETER_VERSION/bin/jmeter.sh -n \
        -t $REMOTE_HOME/execute.jmx \
        -l $REMOTE_HOME/$PROJECT-$DATETIME-$counter.jtl \
        > $LOCAL_HOME/$PROJECT/$DATETIME-${hosts[$counter]}-jmeter.out ) &
    done
    echo
    echo
}

function runtest() {
    # sleep_interval - how often we poll the jmeter output for results
    # this value should be the same as the Generate Summary Results interval set in jmeter.properties
    # to be certain, we read the value in here and adjust the wait to match (this prevents lots of duplicates being written to the screen)
    sleep_interval=$(awk 'BEGIN { FS = "\=" } ; /summariser.interval/ {print $2}' $LOCAL_HOME/jmeter.properties)
    runningtotal_seconds=$(echo "$RUNNINGTOTAL_INTERVAL * $sleep_interval" | bc)
	start_date=$(date)
    echo "JMeter started at $start_date"
    echo "===================================================================== START OF JMETER-EC2 TEST ================================================================================"
    echo "> [updates: every $sleep_interval seconds | running total: every $runningtotal_seconds seconds]"
    echo ">"
    echo "> waiting for the test to start...to stop the test while it is running, press CTRL-C"
    teststarted=1
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
                    echo "> $(date +%T): $screenupdate | host: $host" # write results to screen
                    
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
        
        # every RUNNINGTOTAL_INTERVAL loops print a running summary (if each host is running)
        mod=$(echo "$i % $RUNNINGTOTAL_INTERVAL"|bc)
        if [ $mod == 0 ] ; then
            if [ $firstmodmatch == "TRUE" ] ; then # don't write summary results the first time (because it's not useful)
                firstmodmatch="FALSE"
            else
                # first check the results files to make sure data is available
                wait=0
                for host in ${hosts[@]} ; do
                    result_count=$(grep -c "Results =" $LOCAL_HOME/$PROJECT/$DATETIME-$host-jmeter.out)
                    if [ $result_count = 0 ] ; then
                        wait=1
                    fi
                done
                
                # now write out the data to the screen
                if [ $wait == 0 ] ; then # each file is ready to summarise
                    for host in ${hosts[@]} ; do
                        screenupdate=$(tail -10 $LOCAL_HOME/$PROJECT/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1)
                        echo "> $(date +%T): $screenupdate | host: $host" # write results to screen
                    done
                    echo ">"
                    echo "> $(date +%T): [RUNNING TOTALS] current count: $count_overallhosts, current avg: $avg_overallhosts (ms), current tps: $tps_overallhosts (p/sec), errors: $errors_overallhosts"
                    echo ">"
                fi
            fi
        fi
        i=$(( $i + 1))
        
        sleep $sleep_interval
        
        # we rely on JM to keep track of overall test totals (via Results =) so we only need keep count of values over multiple instances
        # there's no need for a running total outside of this loop so we reinitialise the vars here.
        count_total=0
        avg_total=0
        count_overallhosts=0
        avg_overallhosts=0
        tps_overallhosts=0
        errors_overallhosts=0
        
        # check to see if the test is complete
        res=$(grep -c "end of run" $LOCAL_HOME/$PROJECT/$DATETIME*jmeter.out | awk -F: '{ s+=$NF } END { print s }')
    done # test complete
    
    # now the test is complete calculate a final summary and write to the screen
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
    done
    
    # calculate averages over all hosts
    avg_overallhosts=$(echo "$avg_overallhosts/$INSTANCE_COUNT" | bc)
}

function runcleanup() {
	# Turn off the CTRL-C trap now that we are already in the runcleanup function
	trap - INT 
	
    if [ "$teststarted" -eq 1 ] ; then
        # display final results
        echo ">"
        echo ">"
        echo "> $(date +%T): [FINAL RESULTS] total count: $count_overallhosts, overall avg: $avg_overallhosts (ms), overall tps: $tps_overallhosts (p/sec), errors: $errors_overallhosts"
        echo ">"
        echo "===================================================================== END OF JMETER-EC2 TEST =================================================================================="
        echo
        echo
    fi

      
    # download the results
    for i in ${!hosts[@]} ; do
        echo -n "downloading results from ${hosts[$i]}..."
        scp -q -o UserKnownHostsFile=/dev/null \
                                     -o StrictHostKeyChecking=no \
                                     -i $PEM_PATH/$PEM_FILE.pem \
                                     $USER@${hosts[$i]}:$REMOTE_HOME/$PROJECT-$DATETIME-$i.jtl \
                                     $LOCAL_HOME/$PROJECT/
        echo "$LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-$i.jtl complete"
    done
    echo
    
    
    # terminate any running instances created
    if [ -z "$REMOTE_HOSTS" ]; then
        echo "terminating instance(s)..."
        ec2-terminate-instances ${instanceids[@]}
        echo
    fi
    
    
    # process the files into one jtl results file
    echo -n "processing results..."
    for (( i=0; i<$INSTANCE_COUNT; i++ )) ; do
        cat $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-$i.jtl >> $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-temp.jtl
        rm $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-$i.jtl # removes the individual results files (from each host) - might be useful to some people to keep these files?
    done	
    sort $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-temp.jtl >> $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-sorted.jtl

    # Split the thread label into two columns
    #sed 's/ \([0-9][0-9]*-[0-9][0-9]*,\)/,\1/' \
    #                  $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-sorted.jtl >> \
    #                  $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-complete.jtl

    rm $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-temp.jtl
    mkdir -p $LOCAL_HOME/$PROJECT/results/
    mv $LOCAL_HOME/$PROJECT/$PROJECT-$DATETIME-complete.jtl $LOCAL_HOME/$PROJECT/results/


	#***************************************************************************
	# IMPORT RESULTS TO MYSQL DATABASE - IF SPECIFIED IN PROPERTIES
	# scp import-results.sh
	if [ ! -z "$DB_HOST" ] ; then
	    echo -n "copying import-results.sh to database..."
	    (scp -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
	                                  -i $DB_PEM_PATH/$DB_PEM_FILE.pem \
	                                  $LOCAL_HOME/import-results.sh \
	                                  $DB_PEM_USER@$DB_HOST:$REMOTE_HOME) &
		wait
		echo -n "done...."
	
	    # scp results to remote db
	    echo -n "uploading jtl file to database.."
	    (scp -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r \
	                                  -i $DB_PEM_PATH/$DB_PEM_FILE.pem \
	                                  $LOCAL_HOME/$PROJECT/results/$PROJECT-$DATETIME-complete.jtl \
	                                  $DB_PEM_USER@$DB_HOST:$REMOTE_HOME/import.csv) &
	    wait
	    echo -n "done...."

		# set permissions
	    (ssh -n -o StrictHostKeyChecking=no \
	        -i $DB_PEM_PATH/$DB_PEM_FILE.pem $DB_PEM_USER@$DB_HOST \
			"chmod 755 $REMOTE_HOME/import-results.sh")

	    # Import jtl to database...
	    echo -n "importing jtl file..."
	    (ssh -n -o StrictHostKeyChecking=no \
	        -i $DB_PEM_PATH/$DB_PEM_FILE.pem $DB_PEM_USER@$DB_HOST \
	        "$REMOTE_HOME/import-results.sh \
						'$DB_HOST' \
						'$DB_NAME' \
						'$DB_USER' \
						'$DB_PSWD' \
						'$REMOTE_HOME/import.csv' \
						'$start_date' \
						'myversion' \
						'$PROJECT' \
						'myenvironemt' \
						'a comment'" \
	        > $LOCAL_HOME/$PROJECT/$DATETIME-$host-import.out) &
    
	    # check to see if the install scripts are complete
	    res=0
	    while [ ! "$res" > 0  ] ; do # Import not complete 
	        echo -n .
	        res=$(grep -c "import complete" $LOCAL_HOME/$PROJECT/$DATETIME*import.out \
	            | awk -F: '{ s+=$NF } END { print s }') # the awk command here sums up the output if multiple matches were found
	        sleep 3
	    done
	    echo "done"
    	echo
	fi
	#***************************************************************************
    
    
    # tidy up working files
    # for debugging purposes you could comment out these lines
    rm $LOCAL_HOME/$PROJECT/$DATETIME*.out
    rm $LOCAL_HOME/$PROJECT/working*


    echo "complete"
    echo
    echo
    echo "   -------------------------------------------------------------------------------------"
    echo "                  jmeter-ec2 Automation Script - COMPLETE"
    echo
    echo "   Test Results: $LOCAL_HOME/$PROJECT/results/$PROJECT-$DATETIME-complete.jtl"
    echo "   -------------------------------------------------------------------------------------"
    echo
}

function control_c(){
	# Turn off the CTRL-C trap now that it has been invoked once already
	trap - INT
	
    # Stop the running test on each host
    echo
    echo -n "> Stopping test..."
    for f in ${!hosts[@]} ; do
        ( ssh -nq -o StrictHostKeyChecking=no \
        -i $PEM_PATH/$PEM_FILE.pem $USER@${hosts[$f]} \
        $REMOTE_HOME/$JMETER_VERSION/bin/shutdown.sh ) &
    done
    wait
    echo ">"
    
    runcleanup
    exit
}

# trap keyboard interrupt (control-c)
trap control_c SIGINT

runsetup
runtest
runcleanup
