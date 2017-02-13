#!/bin/bash

# ========================================================================================
# jmeter-ec2.sh
# https://github.com/oliverlloyd/jmeter-ec2
# ========================================================================================
#
# Copyright 2012 - Oliver Lloyd - GNU GENERAL PUBLIC LICENSE
#
# JMeter-ec2 is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# JMeter-ec2 is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with JMeter-ec2.  If not, see <http://www.gnu.org/licenses/>.
#

DATETIME=$(date "+%s")

# First make sure we have the required params and if not print out an instructive message
#if [ -z "$project" ] ; then
if [ "$1" == "-h" ] ; then
	echo 'usage: project="abc" percent=20 setup="TRUE" terminate="TRUE" count="3" ./jmeter-ec2.sh'
	echo
	echo "[project]         -	required, directory and jmx name"
	echo "[count]           -	optional, default=1"
	echo "[percent]         -	optional, default=100"
	echo "[setup]           -	optional, default='TRUE'"
	echo "[terminate]       -	optional, default='TRUE'"
  echo "[price]           - optional"
	echo
	exit
fi

# default to 100 if percent is not specified
if [ -z "$percent" ] ; then percent=100 ; fi

# default to TRUE if setup is not specified
if [ -z "$setup" ] ; then setup="TRUE" ; fi

# default to TRUE if terminate is not specified
if [ -z "$terminate" ] ; then terminate="TRUE" ; fi

# move count to instance_count
if [ -z "$count" ] ; then count=1 ; fi
instance_count=$count

LOCAL_HOME="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Execute the jmeter-ec2.properties file, establishing these constants.
. $LOCAL_HOME/jmeter-ec2.properties

if [ -z "$project" ] ; then
       project=$(basename `pwd`)
fi
project_home=`pwd`

# If exists then run a local version of the properties file to allow project customisations.
if [ -f "$project_home/jmeter-ec2.properties" ] ; then
	. $project_home/jmeter-ec2.properties
fi

cd $EC2_HOME

# check project directory exists
if [ ! -d "$project_home" ] ; then
  echo "The directory $project_home does not exist."
  echo
  echo "Script exiting."
  exit
fi

# The test has not started yet (used to decide what to do when the script stops)
teststarted=0

# do some basic checks to prevent problems later
function check_prereqs() {
	# If there is a custom jmeter.properties, check for:
	# - jmeter.save.saveservice.output_format=csv
	# - jmeter.save.saveservice.thread_counts=true
	if [ -r $LOCAL_HOME/jmeter.properties ] ; then
    has_csv_output=$(grep -c "^\s*jmeter.save.saveservice.output_format=csv"  $LOCAL_HOME/jmeter.properties)
    has_thread_counts=$(grep -c "^\s*jmeter.save.saveservice.thread_counts=true" $LOCAL_HOME/jmeter.properties)
	  if [ $has_csv_output -eq "0" ] ; then
		  echo "WARN: Please ensure the jmeter.properties file has 'jmeter.save.saveservice.output_format=csv'. Could not find it!"
	  fi
	  if [ $has_thread_counts -eq "0" ] ; then
		  echo "WARN: Please ensure the jmeter.properties file has 'jmeter.save.saveservice.thread_counts=true'. Could not find it!"
	  fi
	else
	  echo "WARN: Did not see a custom jmeter.properties file. Please ensure the remote hosts have the required settings 'jmeter.save.saveservice.output_format=csv' and 'jmeter.save.saveservice.thread_counts=true'"
	fi

	# Check that the test plan exists
	if [ -f "$project_home/jmx/$project.jmx" ] ; then
    # Check that the jmx plan has a Generate Summary Reults listener (testclass="Summariser")
    summariser_count=$(grep -c "<Summariser .*testclass=\"Summariser\"" $project_home/jmx/$project.jmx)
    if [ -z $summariser_count ] ; then summariser_count=0 ; fi ;
    if [ $summariser_count -eq "0" ] ; then
      echo "ERROR: Please ensure your JMeter test plan has a Generate Summary Results listener! It is needed for jmeter-ec2 to properly work!"
    fi
	else
    echo "ERROR: Could not find test plan at the following location: $project_home/jmx/$project.jmx"
    exit
	fi

	# Check that awscli is installed and accessible
	if  ! type aws &>/dev/null  ; then
    echo "ERROR: awscli does not appear to be installed or accessible from command line (tried aws)."
    exit
	fi
}

function runsetup() {
  # if REMOTE_HOSTS is not set then no hosts have been specified to run the test on so we will request them from Amazon
  if [ -z "$REMOTE_HOSTS" ] ; then
    # check if ELASTIC_IPS is set, if it is we need to make sure we have enough of them
    if [ ! -z "$ELASTIC_IPS" ] ; then # Not Null - same as -n
      elasticips=(`echo $ELASTIC_IPS | tr "," "\n" | tr -d ' '`)
      elasticips_count=${#elasticips[@]}
      if [ "$instance_count" -gt "$elasticips_count" ] ; then
        echo
        echo "You are trying to launch $instance_count instance but you have only specified $elasticips_count elastic IPs."
        echo "If you wish to use Staitc IPs for each test instance then you must increase the list of values given for ELASTIC_IPS in the properties file."
        echo
        echo "Alternatively, if you set the STATIC_IPS property to \"\" or do not specify it at all then the test will run without trying to assign static IPs."
        echo
        echo "Script exiting..."
        echo
        exit
      fi
    fi

    # default to 1 instance if a count is not specified
    if [ -z "$instance_count" ] ; then instance_count=1; fi

    echo
    echo "   -------------------------------------------------------------------------------------"
    echo "       jmeter-ec2 Automation Script - Running $project.jmx over $instance_count AWS Instance(s)"
    echo "   -------------------------------------------------------------------------------------"
    echo
    echo

    vpcsettings=""
		spot_launch_specification="{
			\"KeyName\": \"$AMAZON_KEYPAIR_NAME\",
			\"ImageId\": \"$AMI_ID\",
			\"InstanceType\": \"$INSTANCE_TYPE\" ,
			\"SecurityGroupIds\": [\"$INSTANCE_SECURITYGROUP_IDS\"]
		}"

		# if subnet is specified
    if [ -n "$SUBNET_ID" ] ; then
			vpcsettings="--subnet-id $SUBNET_ID --associate-public-ip-address"
			spot_launch_specification="{
				\"KeyName\": \"$AMAZON_KEYPAIR_NAME\",
				\"ImageId\": \"$AMI_ID\",
				\"InstanceType\": \"$INSTANCE_TYPE\" ,
				\"SecurityGroupIds\": [\"$INSTANCE_SECURITYGROUP_IDS\"],
				\"SubnetId\": \"$SUBNET_ID\"
			}"
		fi

    # create the instance(s) and capture the instance id(s)
    if [ -z "$price" ] ; then
      echo -n "Requesting $instance_count instance(s)..."
      attempted_instanceids=(`aws ec2 run-instances \
                  --key-name "$AMAZON_KEYPAIR_NAME" \
                  --instance-type "$INSTANCE_TYPE" \
                  --security-group-ids "$INSTANCE_SECURITYGROUP_IDS" \
                  --count 1:$instance_count \
                  $vpcsettings \
                  --image-id $AMI_ID \
                  --region $REGION \
                  --output text --query 'Instances[].InstanceId'`)
    else
      echo "Using Spot instances..."
      # create the spot instance request(s) and capture the request id(s)
      echo "Requesting $instance_count instance(s)..."

      spot_instance_request_id=(`aws ec2 request-spot-instances \
                  --spot-price $price \
                  --instance-count $instance_count \
                  --region $REGION \
                  --launch-specification "$spot_launch_specification" \
                  --output text --query 'SpotInstanceRequests[].[SpotInstanceRequestId]'`)
      echo "Spot Instance request submitted, number of requests is: ${#spot_instance_request_id[@]}"

      status_check_count=0
      status_check_limit=60
      spot_request_fulfilled_count=0
      spot_request_error_count=0
      echo "Waiting for Spot instance requests to fulfill (may take a few minutes)"
      while [ "$spot_request_fulfilled_count" -ne "$instance_count" ] && [ $status_check_count -lt $status_check_limit ]
      do
				spot_request_statuses=(`aws ec2 describe-spot-instance-requests --spot-instance-request-ids ${spot_instance_request_id[@]} --region $REGION --output text --query 'SpotInstanceRequests[].[Status.Code]'`)
				spot_request_fulfilled_count=$(echo ${spot_request_statuses[@]} | tr ' ' '\n' | grep -c fulfilled)

        # if all spot requests failed exit before status_check_limit is reached
        spot_request_errors=(canceled-before-fulfillment capacity-not-available capacity-oversubscribed price-too-low)
        for x in "${spot_request_statuses[@]}" ; do
          for i in "${spot_request_errors[@]}"; do
            if [[ "$i" = "$x" ]]; then
              spot_request_error_count=$(( $spot_request_error_count + 1))
              break
            fi
          done
        done

        if [[ "$spot_request_error_count" = "${#spot_instance_request_id[@]}" ]]; then
          echo
          echo "All Spot requests failed, exiting. Statuses were:"
          for x in "${spot_request_statuses[@]}" ; do
            echo " $x"
          done
          aws ec2 cancel-spot-instance-requests --spot-instance-request-ids $(printf " %s" "${spot_instance_request_id[@]}") --region $REGION
          exit
        fi

        echo -n "."
        status_check_count=$(( $status_check_count + 1))
        sleep 5
      done

      # create a filter for the ec2-describe-instance command, to get the instances associated with the spot requests
			spot_id_filter_values=""
      for x in "${spot_instance_request_id[@]}" ; do
        spot_id_filter_values+="${x},"
      done
			# append values to filter variable and trim last comma off end of string
			spot_id_filter="Name=spot-instance-request-id,Values=${spot_id_filter_values::${#spot_id_filter_values}-1}"

      echo "Will be using this Spot ID filter to find new instances: $spot_id_filter"

      # Instances might not be found immediatly, wait a few seconds if necessary
      status_check_count=0
      status_check_limit=60
      instances_ready=false
      while true; do
        instance_describe=`aws ec2 describe-instances --filters $spot_id_filter --region $REGION`
        if [[ $instance_describe != *"Client.InvalidInstanceID.NotFound"* ]]; then
          instances_ready=true
        fi
        status_check_count=$(( $status_check_count + 1))
        echo "."
        if [ $instances_ready = true ] || [ $status_check_count -gt $status_check_limit ]; then
          break
        fi
      done

      attempted_instanceids=(`aws ec2 describe-instances \
				--filters $spot_id_filter \
				--region $REGION \
				--output text \
				--query 'Reservations[].Instances[].InstanceId'`)
    fi

    # check to see if Amazon returned the desired number of instances as a limit is placed restricting this and we need to handle the case where
    # less than the expected number is given wthout failing the test.
    countof_instanceids=${#attempted_instanceids[@]}
    if [ "$countof_instanceids" = 0 ] ; then
        echo
        echo "Amazon did not supply any instances, exiting"
        echo
        exit
    fi
    if [ $countof_instanceids != $instance_count ] ; then
        echo "$countof_instanceids instance(s) were given by Amazon, the test will continue using only these instance(s)."
        instance_count=$countof_instanceids
    else
        echo "success"
    fi
    echo

    # wait for each instance to be fully operational
    status_check_count=0
    status_check_limit=270
    status_check_limit=`echo "$status_check_limit + $countof_instanceids" | bc` # increase wait time based on instance count
    echo "waiting for instance status checks to pass (this can take several minutes)..."
    count_passed=0
    while [ "$count_passed" -ne "$instance_count" ] && [ $status_check_count -lt $status_check_limit ]
    do
        # Update progress bar
        progressBar $countof_instanceids $count_passed
        status_check_count=$(( $status_check_count + 1))
        count_passed=(`aws ec2 describe-instance-status --instance-ids ${attempted_instanceids[@]} \
				 						 --region $REGION \
										 --output json \
										 --query 'InstanceStatuses[].InstanceStatus.Details[].Status' | grep -c passed`)
				sleep 1
    done
    progressBar $countof_instanceids $count_passed true
    echo

    if [ $status_check_count -lt $status_check_limit ] ; then # all hosts started ok because count_passed==instance_count
      # set the instanceids array to use from now on - attempted = actual
      for key in "${!attempted_instanceids[@]}"
      do
        instanceids["$key"]="${attempted_instanceids["$key"]}"
      done

      # set hosts array
      hosts=(`aws ec2 describe-instances --instance-ids ${attempted_instanceids[@]} \
						--region $REGION \
						--output text \
						--query 'Reservations[].Instances[].PublicIpAddress'`)

      # echo "all hosts ready"
    else # Amazon probably failed to start a host [*** NOTE this is fairly common ***] so show a msg - TO DO. Could try to replace it with a new one?
      original_count=$countof_instanceids
      # filter requested instances for only those that started well
      healthy_instanceids=(`aws ec2 describe-instance-status --instance-id ${attempted_instanceids[@]} \
                          --filter Name=instance-status.reachability,Values=passed \
                          --filter Name=system-status.reachability,Values=passed \
													--region $REGION \
													--output text \
													--query 'Reservations[].Instances[].InstanceId'`)

      hosts=(`aws ec2 describe-instances --instance-ids ${healthy_instanceids[@]} \
						--region $REGION \
						--output text \
						--query 'Reservations[].Instances[].PublicIpAddress'`)

      if [ "${#healthy_instanceids[@]}" -eq 0 ] ; then
        countof_instanceids=0
        echo "no instances successfully initialised, exiting"
        if [ "$terminate" = "TRUE" ] ; then
        	echo
          echo
          # attempt to terminate any running instances - just to be sure
          echo "terminating instance(s)..."
        	# We use attempted_instanceids here to make sure that there are no orphan instances left lying around
          aws ec2 terminate-instances --instance-ids ${attempted_instanceids[@]} \
						--region $REGION \
						--output text \
						--query 'TerminatingInstances[].InstanceId'
          echo
        fi
        exit
      else
        countof_instanceids=${#healthy_instanceids[@]}
      fi

      # if we still see failed instances then write a message
      countof_failedinstances=`echo "$original_count - $countof_instanceids"|bc`
      if [ "$countof_failedinstances" -gt 0 ] ; then
        echo "$countof_failedinstances instances(s) failed to start, only $countof_instanceids machine(s) will be used in the test"
        instance_count=$countof_instanceids
      fi

      # set the array of instance ids based on only those that succeeded
      for key in "${!healthy_instanceids[@]}"  # make sure you include the quotes there
      do
        instanceids["$key"]="${healthy_instanceids["$key"]}"
      done
    fi

    echo

    # assign a name tag to each instance
    echo "assigning tags..."
    (aws ec2 create-tags --resources ${attempted_instanceids[@]} --tags Key=Name,Value="jmeter-ec2-$project" --region $REGION)
    wait
    echo "complete"
    echo

    # if provided, assign elastic IPs to each instance
    if [ ! -z "$ELASTIC_IPS" ] ; then # Not Null - same as -n
      echo "assigning elastic ips..."
      for x in "${!instanceids[@]}" ; do
          (aws ec2 associate-address --instance-id ${instanceids[x]} --public-ip ${elasticips[x]} --region $REGION )
          hosts[x]=${elasticips[x]}
      done
      wait
      echo "complete"
      echo
      echo -n "checking elastic ips..."
      for x in "${!instanceids[@]}" ; do
      # check for ssh connectivity on the new address
      while ssh -o StrictHostKeyChecking=no -q -i $PEM_PATH/$PEM_FILE \
          $USER@${hosts[x]} -p $REMOTE_PORT true && test; \
          do echo -n .; sleep 1; done
      # Note. If any IP is already in use on an instance that is still running then the ssh check above will return
      # a false positive. If this scenario is common you should put a sleep statement here.
      done
      wait
      echo "complete"
      echo
    fi
  else # the property REMOTE_HOSTS is set so we wil use this list of predefined hosts instead
    hosts=(`echo $REMOTE_HOSTS | tr "," "\n" | tr -d ' '`)
    instance_count=${#hosts[@]}
    echo
    echo "   -------------------------------------------------------------------------------------"
    echo "       jmeter-ec2 Automation Script - Running $project.jmx over $instance_count predefined host(s)"
    echo "   -------------------------------------------------------------------------------------"
    echo
    echo

    # Check if remote hosts are up
    for host in ${hosts[@]} ; do
      if [ ! "$(ssh -q \
        -o StrictHostKeyChecking=no \
        -o "BatchMode=yes" \
        -o "ConnectTimeout=15" \
        -i "$PEM_PATH/$PEM_FILE" \
        -p $REMOTE_PORT \
        $USER@$host echo up)" == "up" ] ; then
        echo "Host $host is not responding, script exiting..."
        echo
        exit
      fi
    done
  fi

  # scp verify.sh
  if [ "$setup" = "TRUE" ] ; then
  	echo "copying verify.sh to $instance_count server(s)..."

    for host in ${hosts[@]} ; do
      (scp -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
                    -i "$PEM_PATH/$PEM_FILE" \
                    -P $REMOTE_PORT \
                    $LOCAL_HOME/verify.sh \
                    $LOCAL_HOME/jmeter-ec2.properties \
                    $USER@$host:$REMOTE_HOME \
                    && echo "done" > $project_home/$DATETIME-$host-scpverify.out) &
    done

    # check to see if the scp call is complete (could just use the wait command here...)
    res=0
    while [ "$res" != "$instance_count" ] ;
    do
        # Update progress bar
        progressBar $instance_count $res
        # Count how many out files we have for the copy (if the file exists the copy completed)
        # Note. We send stderr to dev/null in the ls cmd below to prevent file not found errors filling the screen
        # and the sed command here trims whitespace
        res=$(ls -l $project_home/$DATETIME*scpverify.out 2>/dev/null | wc -l | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        sleep 1
    done
    progressBar $instance_count $res true
    echo
    echo

    # Install test software
    echo "running verify.sh on $instance_count server(s)..."
    for host in ${hosts[@]} ; do
      (ssh -nq -o StrictHostKeyChecking=no \
            -i "$PEM_PATH/$PEM_FILE" $USER@$host -p $REMOTE_PORT \
            "$REMOTE_HOME/verify.sh $JMETER_VERSION 2>&1"\
            > $project_home/$DATETIME-$host-verify.out) &
    done

    # check to see if the verify script is complete
    res=0
    while [ "$res" != "$instance_count" ] ; do # Installation not complete (count of matches for 'software installed' not equal to count of hosts running the test)
      # Update progress bar
      progressBar $instance_count $res
      res=$(grep -c "software installed" $project_home/$DATETIME*verify.out \
          | awk -F: '{ s+=$NF } END { print s }') # the awk command here sums up the output if multiple matches were found
      sleep 1
    done
    progressBar $instance_count $res true
    echo
    echo
  fi

  # Create a working jmx file and edit it to adjust thread counts and filepaths (leave the original jmx intact!)
  cp $project_home/jmx/$project.jmx $project_home/working
  working_jmx="$project_home/working"
  temp_jmx="$project_home/temp"

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
        echo "You'll have to remove these from all filepaths. Sorry."
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
  # to cope with the problem of trying to spread 10 threads over 3 hosts (10/3 has a remainder) the script creates a unique jmx for each host
  # and then passes out threads to them on a round robin basis
  # as part of this we begin here by creating a working jmx file for each separate host using _$y to isolate
  for y in "${!hosts[@]}" ; do
    # for each host create a working copy of the jmx file
    cp "$working_jmx" "$working_jmx"_"$y"
  done
  # loop through each threadgroup and then use a nested loop within that to edit the file for each host
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
  echo "editing thread counts..."
  echo
  echo " - $project.jmx has $countofthreadgroups threadgroup(s) - [inc. those disabled]"

  # sum up the thread counts
  sumofthreadgroups=0
  for n in ${!threadgroup_threadcounts[@]} ; do
    # populate an array of the original thread counts (used in the find and replace when editing the jmx)
    orig_threadcounts[$n]=${threadgroup_threadcounts[$n]}
    # create a total of the original thread counts
    sumofthreadgroups=$(echo "$sumofthreadgroups+${threadgroup_threadcounts[$n]}" | bc)
  done

  # adjust each thread count based on percent
  sumofadjthreadgroups=0
  for n in "${!orig_threadcounts[@]}" ; do
    # get a new thread count to 2 decimal places
    float=$(echo "scale=2; ${orig_threadcounts[$n]}*($percent/100)" | bc)
    # round to integer
    new_threadcounts[$n]=$(echo "($float+0.5)/1" | bc)
    if [ "${new_threadcounts[$n]}" -eq "0" ] ; then
    	echo " - Thread group ${threadgroup_names[$n]} has ${orig_threadcounts[$n]} threads, $percent percent of this is $float which rounds to 0, so we're going to set it to 1 instead."
    	new_threadcounts[$n]=1
    	sumofadjthreadgroups=$(echo "$sumofadjthreadgroups+1" | bc)
    fi
  done

  # Now we sum up the thread counts and print a total
  for n in ${!new_threadcounts[@]} ; do
  	sumofadjthreadgroups=$(echo "$sumofadjthreadgroups+${new_threadcounts[$n]}" | bc)
  done

  echo " - There are $sumofthreadgroups threads in the test plan, this test is set to execute $percent percent of these, so will run using $sumofadjthreadgroups threads"

  # now we loop through each thread group, editing a separate file for each host each iteration (nested loop)
  for i in ${!threadgroup_threadcounts[@]} ; do
  	# using modulo we distribute the threads over all hosts, building the array 'threads'
  	# taking 10(threads)/3(hosts) as an example you would expect two hosts to be given 3 threads and one to be given 4.
  	for (( x=1; x<=${new_threadcounts[$i]}; x++ )); do
  		: $(( threads[$(( $x % ${#hosts[@]} ))]++ ))
  	done

  	# here we loop through every host, editing the jmx file and using a temp file to carry the changes over
  	for y in "${!hosts[@]}" ; do
  		# we're already in a loop for each thread group but awk will parse the entire file each time it is called so we need to
  		# use an index to know when to make the edit
  		# when c (awk's index) matches i (the main for loop's index) then a substitution is made

  		# first check for any null values (caused by lots of hosts and not many threads)
  		threadgroupschanged=0
  		if [ -z "${threads[$y]}" ] ; then
  			threads[$y]=1
  			threadgroupschanged=$(echo "$threadgroupschanged+1" | bc)
  		fi
  		if [ "$threadgroupschanged" == "1" ] ; then
  			echo " - $threadgroupschanged thread groups were allocated zero threads, this happens because the total allocated threads to a group is less than the $instance_count instances being used."
  			echo "   To get around this the script gave each group an extra thread, a better solution is to revise the test configuration to use more threads / less instances"
  		fi
  		findstr="threads\">"${orig_threadcounts[$i]}
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

  	# write update to screen - removed 23/04/2012
  	# echo "...$i) ${threadgroup_names[$i]} has ${threadgroup_threadcounts[$i]} thread(s), to be distributed over $instance_count instance(s)"

  	unset threads
  done
  echo
  echo "thread counts updated"
  echo

  # scp the test files onto each host
  echo -n "copying test files to $instance_count server(s)..."

  # scp jmx dir
  echo -n "jmx files.."
  for y in "${!hosts[@]}" ; do
      (scp -q -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r \
                                    -i "$PEM_PATH/$PEM_FILE" -P $REMOTE_PORT \
                                    $project_home/working_$y \
                                    $USER@${hosts[$y]}:$REMOTE_HOME/execute.jmx) &
  done
  wait
  echo -n "done...."

  # scp data dir
  if [ "$setup" = "TRUE" ] ; then
  	if [ -r $project_home/data ] ; then # don't try to upload this optional dir if it is not present
      echo -n "data dir.."
      for host in ${hosts[@]} ; do
          (scp -q -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -r \
                                        -i "$PEM_PATH/$PEM_FILE" -P $REMOTE_PORT \
                                        $project_home/data \
                                        $USER@$host:$REMOTE_HOME/) &
      done
      wait
      echo -n "done...."
    fi

    # scp jmeter.properties
    if [ -r $LOCAL_HOME/jmeter.properties ] ; then # don't try to upload this optional file if it is not present
      echo -n "jmeter.properties.."
      for host in ${hosts[@]} ; do
          (scp -q -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
                                        -i "$PEM_PATH/$PEM_FILE" -P $REMOTE_PORT \
                                        $LOCAL_HOME/jmeter.properties \
                                        $USER@$host:$REMOTE_HOME/$JMETER_VERSION/bin/) &
      done
      wait
      echo -n "done...."
    fi

    # scp system.properties
    if [ -r $LOCAL_HOME/system.properties ] ; then # don't try to upload this optional file if it is not present
      echo -n "system.properties.."
      for host in ${hosts[@]} ; do
          (scp -q -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
                                        -i "$PEM_PATH/$PEM_FILE" -P $REMOTE_PORT \
                                        $LOCAL_HOME/system.properties \
                                        $USER@$host:$REMOTE_HOME/$JMETER_VERSION/bin/) &
      done
      wait
      echo -n "done...."
    fi

    # scp keystore
    if [ -r $LOCAL_HOME/keystore.jks ] ; then # don't try to upload this optional file if it is not present
      echo -n "keystore.jks.."
      for host in ${hosts[@]} ; do
          (scp -q -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
                                        -i "$PEM_PATH/$PEM_FILE" -P $REMOTE_PORT \
                                        $LOCAL_HOME/keystore.jks \
                                        $USER@$host:$REMOTE_HOME) &
      done
      wait
      echo -n "done...."
    fi

    # scp jmeter execution file
    if [ -r $LOCAL_HOME/jmeter ] ; then # don't try to upload this optional file if it is not present
      echo -n "jmeter execution file..."
      for host in ${hosts[@]} ; do
          (scp -q -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
                                        -i "$PEM_PATH/$PEM_FILE" -P $REMOTE_PORT \
                                        $LOCAL_HOME/jmeter $LOCAL_HOME/jmeter \
                                        $USER@$host:$REMOTE_HOME/$JMETER_VERSION/bin/) &
      done
      wait
      echo -n "done...."
    fi

    # scp any custom jar files
    if [ -r $LOCAL_HOME/plugins ] ; then # don't try to upload this optional dir if it is not present
      echo -n "custom jar file(s)..."
      for host in ${hosts[@]} ; do
          (scp -q -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
                                        -i "$PEM_PATH/$PEM_FILE" -P $REMOTE_PORT \
                                        $LOCAL_HOME/plugins/*.jar \
                                        $USER@$host:$REMOTE_HOME/$JMETER_VERSION/lib/ext/) &
      done
      wait
      echo -n "done...."
    fi

    # scp any project specific custom jar files
	    if [ -r $project_home/plugins ] ; then # don't try to upload this optional dir if it is not present
      echo -n "project specific jar file(s)..."
      for host in ${hosts[@]} ; do
          (scp -q -C -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \
                                        -i "$PEM_PATH/$PEM_FILE" -P $REMOTE_PORT \
                                        $project_home/plugins/*.jar \
                                        $USER@$host:$REMOTE_HOME/$JMETER_VERSION/lib/ext/) &
      done
      wait
      echo -n "done...."
    fi

    echo "all files uploaded"
    echo
  fi

  # Start JMeter
  echo "starting jmeter on:"
  for host in ${hosts[@]} ; do
    echo $host
  done
  for counter in ${!hosts[@]} ; do
      ( ssh -nq -o StrictHostKeyChecking=no \
      -p $REMOTE_PORT \
      -i "$PEM_PATH/$PEM_FILE" $USER@${hosts[$counter]} \
      $REMOTE_HOME/$JMETER_VERSION/bin/jmeter.sh -n \
      -t $REMOTE_HOME/execute.jmx \
      -l $REMOTE_HOME/$project-$DATETIME-$counter.jtl \
      >> $project_home/$DATETIME-${hosts[$counter]}-jmeter.out ) &
  done
  echo
  echo
}

function runtest() {
  # sleep_interval - how often we poll the jmeter output for results
  # this value should be the same as the Generate Summary Results interval set in jmeter.properties
  # to be certain, we read the value in here and adjust the wait to match (this prevents lots of duplicates being written to the screen)
  sleep_interval=$(awk 'BEGIN { FS = "=" } ; /summariser.interval/ {print $2}' $LOCAL_HOME/jmeter.properties)
  runningtotal_seconds=$(echo "$RUNNINGTOTAL_INTERVAL * $sleep_interval" | bc)
	# $epoch is used when importing to mysql (if enabled) because we want unix timestamps, not datetime, as this works better when graphing.
	epoch_seconds=$(date +%s)
	epoch_milliseconds=$(echo "$epoch_seconds* 1000" | bc) # milliseconds since Mick Jagger became famous
	start_date=$(date) # warning, epoch and start_date do not (absolutely) equal each other!

  echo "JMeter started at $start_date"
  echo "====================== START OF JMETER-EC2 TEST ================================="
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
  while [ $res != $instance_count ] ; do # test not complete (count of matches for 'end of run' not equal to count of hosts running the test)
    # gather results data and write to screen for each host
    #while read host ; do
    for host in ${hosts[@]} ; do
      check=$(tail -10 $project_home/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $1}') # make sure the test has really started to write results to the file
      if [[ -n "$check" ]] ; then # not null
        if [ $check == "Generate" ] ; then # test has begun
          screenupdate=$(tail -10 $project_home/$DATETIME-$host-jmeter.out | grep "Results +" | tail -1)
          echo "> $(date +%T): $screenupdate | host: $host" # write results to screen

          # get the latest values
          count=$(tail -10 $project_home/$DATETIME-$host-jmeter.out | grep "Results +" | tail -1 | awk '{print $5}') # pull out the current count
          avg=$(tail -10 $project_home/$DATETIME-$host-jmeter.out | grep "Results +" | tail -1 | awk '{print $11}') # pull out current avg
          tps_raw=$(tail -10 $project_home/$DATETIME-$host-jmeter.out | grep "Results +" | tail -1 | awk '{print $9}') # pull out current tps
          errors_raw=$(tail -10 $project_home/$DATETIME-$host-jmeter.out | grep "Results +" | tail -1 | awk '{print $17}') # pull out current errors
          tps=${tps_raw%/s} # remove the trailing '/s'

          # get the latest summary values
          count_total=$(tail -10 $project_home/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $5}')
          avg_total=$(tail -10 $project_home/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $11}')
          tps_total_raw=$(tail -10 $project_home/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $9}')
          tps_recent_raw=$(tail -10 $project_home/$DATETIME-$host-jmeter.out | grep "Results +" | tail -1 | awk '{print $9}')
          tps_total=${tps_total_raw%/s} # remove the trailing '/s'
          tps_recent=${tps_recent_raw%/s} # remove the trailing '/s'
          errors_total=$(tail -10 $project_home/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $17}')

          count_overallhosts=$(echo "$count_overallhosts+$count_total" | bc) # add the value from this host to the values from other hosts
          avg_overallhosts=$(echo "$avg_overallhosts+$avg" | bc)
          tps_overallhosts=$(echo "$tps_overallhosts+$tps_total" | bc)
          tps_recent_overallhosts=$(echo "$tps_recent_overallhosts+$tps_recent" | bc)
          errors_overallhosts=$(echo "$errors_overallhosts+$errors_total" | bc) # add the value from this host to the values from other hosts
        fi
      fi
    done #<<<"${hosts_str}" # next host

    # calculate the average respone time over all hosts
    avg_overallhosts=$(echo "$avg_overallhosts/$instance_count" | bc)

    # every RUNNINGTOTAL_INTERVAL loops print a running summary (if each host is running)
    mod=$(echo "$i % $RUNNINGTOTAL_INTERVAL"|bc)
    if [ $mod == 0 ] ; then
      if [ $firstmodmatch == "TRUE" ] ; then # don't write summary results the first time (because it's not useful)
        firstmodmatch="FALSE"
      else
        # first check the results files to make sure data is available
        wait=0
        for host in ${hosts[@]} ; do
          result_count=$(grep -c "Results =" $project_home/$DATETIME-$host-jmeter.out)
          if [ $result_count = 0 ] ; then
            wait=1
          fi
        done

        # now write out the data to the screen
        if [ $wait == 0 ] ; then # each file is ready to summarise
          for host in ${hosts[@]} ; do
            screenupdate=$(tail -10 $project_home/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1)
            echo "> $(date +%T): $screenupdate | host: $host" # write results to screen
          done
          echo ">"
          echo "> $(date +%T): [RUNNING TOTALS] total count: $count_overallhosts, current avg: $avg_overallhosts (ms), average tps: $tps_overallhosts (p/sec), recent tps: $tps_recent_overallhosts (p/sec), total errors: $errors_overallhosts"
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
    tps_recent_overallhosts=0
    errors_overallhosts=0

    # check to see if the test is complete
    res=$(grep -c "end of run" $project_home/$DATETIME*jmeter.out | awk -F: '{ s+=$NF } END { print s }')
  done # test complete

  # now the test is complete calculate a final summary and write to the screen
  for host in ${hosts[@]} ; do
    # get the final summary values
    count_total=$(tail -10 $project_home/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $5}')
    avg_total=$(tail -10 $project_home/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $11}')
    tps_total_raw=$(tail -10 $project_home/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $9}')
    tps_total=${tps_total_raw%/s} # remove the trailing '/s'
    tps_recent_raw=$(tail -10 $project_home/$DATETIME-$host-jmeter.out | grep "Results +" | tail -1 | awk '{print $9}')
    tps_recent=${tps_recent_raw%/s} # remove the trailing '/s'
    errors_total=$(tail -10 $project_home/$DATETIME-$host-jmeter.out | grep "Results =" | tail -1 | awk '{print $17}')

    # running totals
    count_overallhosts=$(echo "$count_overallhosts+$count_total" | bc) # add the value from this host to the values from other hosts
    avg_overallhosts=$(echo "$avg_overallhosts+$avg_total" | bc)
    tps_overallhosts=$(echo "$tps_overallhosts+$tps_total" | bc) # add the value from this host to the values from other hosts
    tps_recent_overallhosts=$(echo "$tps_recent_overallhosts+$tps_recent" | bc)
    errors_overallhosts=$(echo "$errors_overallhosts+$errors_total" | bc) # add the value from this host to the values from other hosts
  done

  # calculate averages over all hosts
  avg_overallhosts=$(echo "$avg_overallhosts/$instance_count" | bc)
}

function runcleanup() {
	# Turn off the CTRL-C trap now that we are already in the runcleanup function
	trap - INT

  if [ "$teststarted" -eq 1 ] ; then
    # display final results
    echo ">"
    echo ">"
    echo "> $(date +%T): [FINAL RESULTS] total count: $count_overallhosts, overall avg: $avg_overallhosts (ms), overall tps: $tps_overallhosts (p/sec), recent tps: $tps_recent_overallhosts (p/sec), errors: $errors_overallhosts"
    echo ">"
    echo "===================================================================== END OF JMETER-EC2 TEST =================================================================================="
    echo
    echo

    # download the results
    for i in ${!hosts[@]} ; do
      echo -n "downloading results from ${hosts[$i]}..."
      scp -q -C -o UserKnownHostsFile=/dev/null \
                                   -o StrictHostKeyChecking=no \
                                   -i "$PEM_PATH/$PEM_FILE" \
                                   -P $REMOTE_PORT \
                                   $USER@${hosts[$i]}:$REMOTE_HOME/$project-*.jtl \
                                   $project_home/
      # Append the hostname
      sed "s/$/,"${hosts[$i]}"/" $project_home/$project-$DATETIME-$i.jtl >> $project_home/$project-$DATETIME-$i-appended.jtl
      rm $project_home/$project-$DATETIME-$i.jtl
      echo "$project_home/$project-$DATETIME-$i.jtl complete"
    done
    echo

    # process the files into one jtl results file
    echo -n "processing results..."
    for (( i=0; i<$instance_count; i++ )) ; do
      cat $project_home/$project-$DATETIME-$i-appended.jtl >> $project_home/$project-$DATETIME-grouped.jtl
      rm $project_home/$project-$DATETIME-$i-appended.jtl # removes the individual results files (from each host) - might be useful to some people to keep these files?
    done

    # Sort File
    sort $project_home/$project-$DATETIME-grouped.jtl >> $project_home/$project-$DATETIME-sorted.jtl

    # Remove blank lines
    sed '/^$/d' $project_home/$project-$DATETIME-sorted.jtl >> $project_home/$project-$DATETIME-noblanks.jtl

    # Remove any lines containing "0,0,Error:" - which seems to be an intermittant bug in JM where the getTimestamp call fails with a nullpointer
    sed '/^0,0,Error:/d' $project_home/$project-$DATETIME-noblanks.jtl >> $project_home/$project-$DATETIME-complete.jtl

    # Calclulate test duration
    start_time=$(head -1 $project_home/$project-$DATETIME-complete.jtl | cut -d',' -f1)
    end_time=$(tail -1 $project_home/$project-$DATETIME-complete.jtl | cut -d',' -f1)
    duration=$(echo "$end_time-$start_time" | bc)
    if ! [ "$duration" -gt 0 ] ; then
      duration=0;
    fi
  fi

  # terminate any running instances created
  if [ -z "$REMOTE_HOSTS" ]; then
  	if [ "$terminate" = "TRUE" ] ; then
      echo
      echo
      echo "terminating instance(s)..."
      # We use attempted_instanceids here to make sure that there are no orphan instances left lying around
			aws ec2 terminate-instances --instance-ids ${attempted_instanceids[@]} \
				--region $REGION \
				--output text \
				--query 'TerminatingInstances[].InstanceId'
      echo
  	fi
  fi

	# Tidy up
  if [ -e "$project_home/$project-$DATETIME-grouped.jtl" ] ; then rm $project_home/$project-$DATETIME-grouped.jtl ; fi
  if [ -e "$project_home/$project-$DATETIME-sorted.jtl" ] ; then rm $project_home/$project-$DATETIME-sorted.jtl ; fi
  if [ -e "$project_home/$project-$DATETIME-noblanks.jtl" ] ; then rm $project_home/$project-$DATETIME-noblanks.jtl ; fi
  if [ -e "$project_home/$project-$DATETIME-complete.jtl" ] ; then
    mkdir -p $project_home/results/
    mv $project_home/$project-$DATETIME-complete.jtl $project_home/results/
  fi

  # tidy up working files
  # for debugging purposes you could comment out these lines
  rm $project_home/$DATETIME*.out
  rm $project_home/working*


  echo
  echo "   -------------------------------------------------------------------------------------"
  echo "                  jmeter-ec2 Automation Script - COMPLETE"
  echo
  if [ "$teststarted" -eq 1 ] ; then
    echo "   Test Results: $project_home/results/$project-$DATETIME-complete.jtl"
  fi
  echo "   -------------------------------------------------------------------------------------"
  echo
}


progressBarWidth=50
spinnerIndex=1
sp="/-\|"

# Function to draw progress bar
progressBar() {
  taskCount=$1
  tasksDone=$2
  progressDone=$3
  # Calculate number of fill/empty slots in the bar
  progress=$(echo "$progressBarWidth/$taskCount*$tasksDone" | bc -l)
  fill=$(printf "%.0f\n" $progress)
  if [ $fill -gt $progressBarWidth ]; then
    fill=$progressBarWidth
  fi
  empty=$(($fill-$progressBarWidth))

  # Percentage Calculation
  progressPercent=$(echo "100/$taskCount*$tasksDone" | bc -l)
  progressPercent=$(printf "%0.2f\n" $progressPercent)
  if [[ -n "${progressPercent}" && $(echo "$progressPercent>100" | bc) -gt 0 ]]; then
    progressPercent="100.00"
  fi

  # Output to screen
  printf "\r["
  printf "%${fill}s" '' | tr ' ' \#
  printf "%${empty}s" '' | tr ' ' " "
  printf "] $progressPercent%% - ($tasksDone of $taskCount) "
  if [ $progressDone ] ; then
    printf " - Done."
  else
    printf " \b${sp:spinnerIndex++%${#sp}:1} "
  fi
}

function control_c(){
	# Turn off the CTRL-C trap now that it has been invoked once already
	trap - INT

  if [ "$teststarted" -eq 1 ] ; then
    # Stop the running test on each host
    echo
    echo "> Stopping test..."
    for f in ${!hosts[@]} ; do
        ( ssh -nq -o StrictHostKeyChecking=no \
        -i "$PEM_PATH/$PEM_FILE" $USER@${hosts[$f]} -p $REMOTE_PORT \
        $REMOTE_HOME/$JMETER_VERSION/bin/stoptest.sh ) &
    done
    wait
    echo ">"
  fi

  runcleanup
  exit
}

# trap keyboard interrupt (control-c)
trap control_c SIGINT

check_prereqs
runsetup
runtest
runcleanup
