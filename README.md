# MongoDB
Collection of scripts to manage MongoDB.

## Backups
The main MongoDB backup [script](mongo_backup.sh) has several cool features:
1. It has no external server dependencies and runs completely within the Amazon ecosystem
    1. For example, it uses SES for email notifications, not SMTP
    1. It streams directly to S3 and creates no temporary files
1. Further, it ensures that only one backup will run at any given time
1. Finally, it uses a standard syslog logger to log all its messages

