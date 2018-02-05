#!/bin/bash

#we need this to ensure errors are propagated downstream
#through all the pipes
set -o pipefail

#define the constants
connectionString="rs0/prod01:27017,prod02:27017,prod03:27017"
backupUserName=backup_user
backupPassword=mybackuppassword
dateTimeStamp=$(date "+%Y.%m.%d-%H.%M.%S")
bucketName=mongobackups
environment=PROD
fromAddress="notify@email.com"
hostname=$(hostname)
archiveName=mongobackup-"$dateTimeStamp"-"$hostname".gz
currentYear=$(date "+%Y")
currentMonth=$(date "+%m")
s3path=s3://"$bucketName"/MongoDB/"$environment"/"$currentYear"/"$currentMonth"/"$archiveName"

#define the functions
#mongodump -u "$backupUserName" -p "$backupPassword" --host "$connectionString" --archive=mongo_dumps/"$archiveName" --gzip --oplog
function create_json_message {
  cat <<EOF > ./message.json
    {
     "Subject": {
       "Data": "ERROR: Failed Mongo database backup on $HOSTNAME",
       "Charset": "UTF-8"
    },
    "Body": {
       "Text": {
           "Data": "$DateTimeStamp: $1",
           "Charset": "UTF-8"
       }
     }
   }
EOF
}

function create_destination_email {
  cat <<EOF > ./destination.json
  {
    "ToAddresses":  ["notify@email.com"],
    "BccAddresses": []
  }
EOF
}

function send_email {
  aws ses send-email --from "$fromAddress" --destination file://destination.json --message file://message.json
}

function error_handler {
 #Spaces in error messages trip up the field separator, so we are preserving the old one
 #and changing the IFS temporarily
 SAVEIFS=$IFSIFS=$(echo -en "\n\b")
 IFS=$(echo -en "\n\b")

 errMessage="$1"

 #log the error to /var/log/messages
 echo "$errMessage" | logger

 #create the json email body file for the aws SES with the passed error message
 create_json_message $errMessage

 #create the json destination file for the aws ses
 create_destination_email

 #send the email
 send_email
 IFS=$SAVEIFS
}

#capture all errors and stdout and send them all to syslog /var/log/messages
exec 1> >(logger -t "mongodump") 2> >(logger -t "mongodump")

#get an exclusive lock to make sure only 1 backup runs at a time
exec 9>/home/ec2-user/backups/.mongo.backup.exclusive.lock
if ! flock -n 9  ; then
           echo "Another mongo backup instance is running, exiting";
              exit 1
      fi
# this now runs under the lock until 9 is closed (it will be closed automatically when the script ends)
mongodump -u "$backupUserName" -p "$backupPassword" --host "$connectionString" --archive --gzip --oplog | aws s3 cp - "$s3path"

if [ $? -ne 0 ]; then
    error_handler "There was an issue running mongodump on $hostname"
    exit
fi
