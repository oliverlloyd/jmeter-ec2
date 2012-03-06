#!/bin/bash

RESULTS_FILE=$1
STARTDATE=$2
BUILDLIFE=$3
PROJECT=$4
ENVIRONMENT=$5
COMMENT=$6


# Create table if not there already, results and tests



# Insert a new row in tests table,
search_value=$BUILDLIFE-$PROJECT-$ENVIRONMENT-$STARTDATE-$COMMENT

sqlInsertTestid="INSERT INTO jmeter.tests (buildlife, project, environment, value4, comment, startdate) VALUES ('$BUILDLIFE', '$PROJECT', '$ENVIRONMENT', '$search_value', '$COMMENT', '$STARTDATE');"

mysql -u root jmeter << eof
$sqlInsertTestid
eof


# Import Results File
sqlImport="load data local infile '$RESULTS_FILE' \
			into table jmeter.results fields terminated by ',' \
			enclosed by '\"' lines terminated by '\n' \
			(timestamp,elapsed,label,responsecode,responsemessage,threadname,datatype,success,bytes,grpthreads,allthreads,latency,hostname)"

#mysql -u root jmeter << eof
#$sqlImport
#eof
			
# Get last testid
sqlGetMaxTestid="SELECT max(testid) from jmeter.tests"

result=$(mysql -u root jmeter << eof
$sqlGetMaxTestid
eof)

echo $result

newTestid=$(echo $result | cut -d ' ' -f2)

echo $newTestid


# Update Testid in results
sqlUpdateTestid="UPDATE jmeter.results SET testid = $newTestid WHERE testid IS NULL AND id > 0"

result=$(mysql -u root jmeter << eof
$sqlUpdateTestid
eof)






