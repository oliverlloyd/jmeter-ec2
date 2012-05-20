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
shift 2
COMMENT=$8
DURATION=$9

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



# Create tests table if not there already, results and tests

sqlcreate="CREATE TABLE IF NOT EXISTS  tests ( \
  testid int(11) NOT NULL AUTO_INCREMENT, \
  buildlife varchar(45) DEFAULT NULL, \
  project varchar(45) DEFAULT NULL, \
  environment varchar(45) DEFAULT NULL, \
  duration varchar(45) DEFAULT NULL, \
  comment varchar(45) DEFAULT NULL, \
  startdate varchar(45) DEFAULT NULL, \
  accepted varchar(45) DEFAULT NULL, \
  value8 varchar(45) DEFAULT NULL, \
  value9 varchar(45) DEFAULT NULL, \
  value10 varchar(45) DEFAULT NULL, \
  PRIMARY KEY (testid) \
) ENGINE=MyISAM AUTO_INCREMENT=2 DEFAULT CHARSET=latin1;"

dosql "$sqlcreate"


# Insert a new row in tests table,
#search_value=$BUILDLIFE-$PROJECT-$ENVIRONMENT-$STARTDATE-$COMMENT

sqlInsertTestid="INSERT INTO $mysql_db.tests (buildlife, project, environment, duration, comment, startdate, accepted) VALUES ('$BUILDLIFE', '$PROJECT', '$ENVIRONMENT', '$DURATION', '$COMMENT', '$STARTDATE', 'N');"

dosql "$sqlInsertTestid"




# Import Results File
sqlImport="load data local infile '$RESULTS_FILE' \
			into table $mysql_db.results fields terminated by ',' \
			enclosed by '\"' lines terminated by '\n' \
			(timestamp,elapsed,label,responsecode,responsemessage,threadname,datatype,success,bytes,grpthreads,allthreads,latency,hostname)"

dosql "$sqlImport"


# Get last testid
sqlGetMaxTestid="SELECT max(testid) from $mysql_db.tests"

dosql "$sqlGetMaxTestid"

newTestid=$(echo $sqlresult | cut -d ' ' -f2)

echo "new testid = "$newTestid

# Update Testid in results
sqlUpdateTestid="UPDATE $mysql_db.results SET testid = $newTestid WHERE testid IS NULL AND id > 0"

dosql "$sqlUpdateTestid"

echo 'import complete';