#!/bin/bash


debug=true
#debug=false

DB_HOST=$1
DB_NAME=$2
DB_USER=$3
DB_PSWD=$4
RESULTS_FILE=$5
STARTDATE=$6
BUILDLIFE=$7
PROJECT=$8
ENVIRONMENT=$9
shift 3
COMMENT=$7
DURATION=$8
TESTID=$9

echo "DB_HOST: $DB_HOST"
echo "DB_NAME: $DB_NAME"
echo "DB_USER: $DB_USER"
echo "DB_PSWD: $DB_PSWD"
echo "RESULTS_FILE: $RESULTS_FILE"
echo "STARTDATE: $STARTDATE"
echo "BUILDLIFE: $BUILDLIFE"
echo "PROJECT: $PROJECT"
echo "ENVIRONMENT: $ENVIRONMENT"
echo "COMMENT: $COMMENT"
echo "DURATION: $DURATION"
echo "TESTID: $TESTID"


sqlstr="mysql -u $DB_USER -h $DB_HOST -p$DB_PSWD $DB_NAME"

function dosql {
	sqlresult=$($sqlstr -e "$1")
	if [ $debug = "true" ]; then
		echo "sqlstmt = '"$1"'"
		echo "sqlresult = '"$sqlresult"'"
	fi

}


# Create results table if not there already

sqlcreate="CREATE TABLE IF NOT EXISTS results ( \
  id int(11) NOT NULL AUTO_INCREMENT, \
  testid int(11) DEFAULT NULL, \
  timestamp varchar(45) DEFAULT NULL, \
  elapsed varchar(45) DEFAULT NULL, \
  label varchar(45) DEFAULT NULL, \
  responsecode varchar(45) DEFAULT NULL, \
  responsemessage varchar(45) DEFAULT NULL, \
  threadname varchar(45) DEFAULT NULL, \
  datatype varchar(45) DEFAULT NULL, \
  success varchar(45) DEFAULT NULL, \
  bytes varchar(45) DEFAULT NULL, \
  grpthreads varchar(45) DEFAULT NULL, \
  allthreads varchar(45) DEFAULT NULL, \
  latency varchar(45) DEFAULT NULL, \
  hostname varchar(45) DEFAULT NULL, \
  PRIMARY KEY (id) \
) ENGINE=MyISAM AUTO_INCREMENT=0 DEFAULT CHARSET=latin1;"

dosql "$sqlcreate"


# Import Results File
sqlImport="load data local infile '$RESULTS_FILE' \
			into table $mysql_db.results fields terminated by ',' \
			enclosed by '\"' lines terminated by '\n' \
			(testid,timestamp,elapsed,label,responsecode,responsemessage,threadname,datatype,success,bytes,grpthreads,allthreads,latency,hostname)"

dosql "$sqlImport"


echo 'import complete';