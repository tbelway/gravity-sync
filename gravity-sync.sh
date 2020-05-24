#!/bin/bash

# GRAVITY SYNC BY VMSTAN #####################
PROGRAM='Gravity Sync'
VERSION='1.3.0'

# Must execute from a location in the home folder of the user who own's it (ex: /home/pi/gravity-sync)
# Configure certificate based SSH authentication between the Pi-hole HA nodes - it does not use passwords
# Tested against Pihole 5.0 GA on Raspbian Buster and Ubuntu 20.04, but it should work on most configs
# More installation instructions available at https://vmstan.com/gravity-sync
# For the latest version please visit https://github.com/vmstan/gravity-sync under Releases

# REQUIRED SETTINGS ##########################

# You MUST define REMOTE_HOST and REMOTE_USER in a file called 'gravity-sync.conf' OK
# You can copy the 'gravity-sync.conf.example' file in the script directory to get started 

# STANDARD VARIABLES #########################

# GS Folder/File Locations
LOCAL_FOLDR='gravity-sync' # must exist in running user home folder
CONFIG_FILE='gravity-sync.conf' # must exist as explained above
SYNCING_LOG='gravity-sync.log' # will be created in above folder
CRONTAB_LOG='gravity-sync.cron'
BACKUP_FOLD='backup'

# PH Folder/File Locations
PIHOLE_DIR='/etc/pihole'  # default install directory
GRAVITY_FI='gravity.db' # this should not change

##############################################
### DO NOT CHANGE ANYTHING BELOW THIS LINE ###
##############################################

# Script Colors
RED='\033[0;91m'
GREEN='\033[0;92m'
CYAN='\033[0;96m'
YELLOW='\033[0;93m'
PURPLE='\033[0;95m'
NC='\033[0m'

# Message Codes
FAIL="[${RED}FAIL${NC}]"
WARN="[${PURPLE}WARN${NC}]"
GOOD="[${GREEN}GOOD${NC}]"
STAT="[${CYAN}EXEC${NC}]"
INFO="[${YELLOW}INFO${NC}]"

# FUNCTION DEFINITIONS #######################

# Import Settings
function import_gs {
	echo -e "[${CYAN}STAT${NC}] Importing ${CONFIG_FILE} Settings"
	if [ -f $HOME/${LOCAL_FOLDR}/${CONFIG_FILE} ]
	then
	    source $HOME/${LOCAL_FOLDR}/${CONFIG_FILE}
		echo -e "[${GREEN}GOOD${NC}] Using ${REMOTE_USER}@${REMOTE_HOST}"
	else
		echo -e "[${RED}FAIL${NC}] Required ${CONFIG_FILE} Missing"
		echo -e "Please review installation documentation for more information"
		exit_nochange
	fi
}

# Update Function
function update_gs {
	TASKTYPE='UPDATE'
	logs_export 	# dumps log prior to execution because script stops after successful pull
	echo -e "[${PURPLE}WARN${NC}] Requires GitHub Installation"
		git reset --hard
		git pull
	exit
}

# Pull Function
function pull_gs {
	TASKTYPE='PULL'
	
	MESSAGE="Pulling ${GRAVITY_FI} from ${REMOTE_HOST}"
	echo -e "${STAT} ${MESSAGE}"
		rsync -v -e 'ssh -p 22' ${REMOTE_USER}@${REMOTE_HOST}:${PIHOLE_DIR}/${GRAVITY_FI} $HOME/${LOCAL_FOLDR}/${BACKUP_FOLD}/${GRAVITY_FI}.pull
		error_validate
	
	MESSAGE="Backing Up ${GRAVITY_FI} on $HOSTNAME"
	echo -e "${STAT} ${MESSAGE}"
		cp -v ${PIHOLE_DIR}/${GRAVITY_FI} $HOME/${LOCAL_FOLDR}/${BACKUP_FOLD}/${GRAVITY_FI}.backup
		error_validate
	
	MESSAGE="Replacing ${GRAVITY_FI} on $HOSTNAME"
	echo -e "${STAT} ${MESSAGE}"	
		sudo cp -v $HOME/${LOCAL_FOLDR}/${BACKUP_FOLD}/${GRAVITY_FI}.pull ${PIHOLE_DIR}/${GRAVITY_FI}
		error_validate
	
	MESSAGE="Setting Permissions on ${GRAVITY_FI}"
	echo -e "${STAT} ${MESSAGE}"	
		sudo chmod 644 ${PIHOLE_DIR}/${GRAVITY_FI}
		error_validate
		
	MESSAGE="Setting Ownership on ${GRAVITY_FI}"
	echo -e "${STAT} ${MESSAGE}"	
		sudo chown pihole:pihole ${PIHOLE_DIR}/${GRAVITY_FI}
		error_validate	
	
	MESSAGE="Reloading FTLDNS Configuration"
	echo -e "${STAT} ${MESSAGE}"
		pihole restartdns reloadlists
		pihole restartdns
		error_validate
	
	logs_export
	exit_withchange
}

# Push Function
function push_gs {
	TASKTYPE='PUSH'
	echo -e "${WARN} DATA LOSS IS POSSIBLE"
	echo -e "The standard use of this script is to ${YELLOW}PULL${NC} data from the" 
	echo -e "primary PH server to the secondary. By issuing a ${YELLOW}PUSH${NC}, we" 
	echo -e "will instead overwrite the ${GRAVITY_FI} on ${YELLOW}${REMOTE_HOST}${NC}"
	echo -e "with ${YELLOW}$HOSTNAME${NC} server data. A copy of the remote ${GRAVITY_FI}"
	echo -e "will be saved to this server at:"
	echo -e "${YELLOW}$HOME/${LOCAL_FOLDR}/${BACKUP_FOLD}/${GRAVITY_FI}.push${NC}"
	echo -e ""
	echo -e "Are you sure you want to overwrite the primary node configuration on ${REMOTE_HOST}?"
	select yn in "Yes" "No"; do
		case $yn in
		Yes )
			
			MESSAGE="Backing Up ${GRAVITY_FI} from ${REMOTE_HOST}"
			echo -e "${STAT} ${MESSAGE}"
				rsync -v -e 'ssh -p 22' ${REMOTE_USER}@${REMOTE_HOST}:${PIHOLE_DIR}/${GRAVITY_FI} $HOME/${LOCAL_FOLDR}/${BACKUP_FOLD}/${GRAVITY_FI}.push
				error_validate
	
			MESSAGE="Pushing ${GRAVITY_FI} to ${REMOTE_HOST}"
			echo -e "${STAT} ${MESSAGE}"
				rsync --rsync-path="sudo rsync" -v -e 'ssh -p 22' ${PIHOLE_DIR}/${GRAVITY_FI} ${REMOTE_USER}@${REMOTE_HOST}:${PIHOLE_DIR}/${GRAVITY_FI}
				error_validate
	
			MESSAGE="Setting Permissions on ${GRAVITY_FI}"
			echo -e "${STAT} ${MESSAGE}"	
				ssh ${REMOTE_USER}@${REMOTE_HOST} "sudo chmod 644 ${PIHOLE_DIR}/${GRAVITY_FI}"
				error_validate
		
			MESSAGE="Setting Ownership on ${GRAVITY_FI}"
			echo -e "${STAT} ${MESSAGE}"	
				ssh ${REMOTE_USER}@${REMOTE_HOST} "sudo chown pihole:pihole ${PIHOLE_DIR}/${GRAVITY_FI}"
				error_validate	
	
			MESSAGE="Reloading FTLDNS Configuration"
			echo -e "${STAT} ${MESSAGE}"
				ssh ${REMOTE_USER}@${REMOTE_HOST} 'pihole restartdns reloadlists'
				ssh ${REMOTE_USER}@${REMOTE_HOST} 'pihole restartdns'
				error_validate
			
			logs_export
			exit_withchange
		;;
		
		No )
			exit_nochange
		;;
		esac
	done
}

# Logging Functions
## Check Log Function
function logs_gs {
	echo -e "Recent ${YELLOW}PULL${NC} attempts"
		tail -n 10 ${SYNCING_LOG} | grep PULL
	echo -e "Recent ${YELLOW}UPDATE${NC} attempts"
		tail -n 10 ${SYNCING_LOG} | grep UPDATE
	echo -e "Recent ${YELLOW}PUSH${NC} attempts"
			tail -n 10 ${SYNCING_LOG} | grep PUSH
	exit_nochange
}

## Check Last Crontab
function logs_crontab {
	echo -e "========================================================"
	echo -e "========================================================"
	echo -e ""
	cat ${CRONTAB_LOG}
	echo -e ""
	echo -e "========================================================"
	echo -e "========================================================"
}

## Log Out
function logs_export {
	echo -e "[${CYAN}STAT${NC}] Logging Timestamps to ${SYNCING_LOG}"
	# date >> $HOME/${LOCAL_FOLDR}/${SYNCING_LOG}
	echo -e $(date) "[${TASKTYPE}]" >> $HOME/${LOCAL_FOLDR}/${SYNCING_LOG}
}

# Validate Functions
## Validate GS Folders
function validate_gs_folders {
	if [ -d $HOME/${LOCAL_FOLDR} ]
	then
	    echo -e "[${GREEN}GOOD${NC}] Required $HOME/${LOCAL_FOLDR} Located"
	else
		echo -e "[${RED}FAIL${NC}] Required $HOME/${LOCAL_FOLDR} Missing"
		exit_nochange
	fi
	
	if [ -d $HOME/${LOCAL_FOLDR}/${BACKUP_FOLD} ]
	then
	    echo -e "[${GREEN}GOOD${NC}] Required $HOME/${LOCAL_FOLDR}/${BACKUP_FOLD} Located"
	else
		echo -e "[${RED}FAIL${NC}] Required $HOME/${LOCAL_FOLDR}/${BACKUP_FOLD} Missing"
		exit_nochange
	fi
}

## Validate PH Folders
function validate_ph_folders {
	if [ -d ${PIHOLE_DIR} ]
	then
	    echo -e "[${GREEN}GOOD${NC}] Required ${PIHOLE_DIR} Located"
	else
		echo -e "[${RED}FAIL${NC}] Required ${PIHOLE_DIR} Missing"
		exit_nochange
	fi
}

# List GS Arguments
function list_gs_arguments {
	echo -e "Usage: $0 [options]"
	echo -e "Example: '$0 pull'"
	echo -e ""
	echo -e "Replication Options:"
	echo -e " ${YELLOW}pull${NC}		Sync the ${GRAVITY_FI} configuration on primary PH to this server"
	echo -e " ${YELLOW}push${NC}		Force any changes made on this server back to the primary PH"
	echo -e ""
	echo -e "Debugging Options:"
	echo -e " ${YELLOW}update${NC}		Use GitHub to update this script to the latest version available"
	echo -e " ${YELLOW}version${NC}	Display the version of the current installed script"
	echo -e " ${YELLOW}logs${NC}		Show recent successful jobs"
	echo -e ""
	exit_nochange
}

# Exit Codes
## No Changes Made
function exit_nochange {
	echo -e "${INFO} ${PROGRAM} ${YELLOW}${TASKTYPE}${NC} Exiting Without Changes"
	exit 0
}

## Changes Made
function exit_withchange {
	echo -e "${GOOD} ${PROGRAM} ${YELLOW}${TASKTYPE}${NC} Completed"
	exit 0
}

# Error Validation
function error_validate {
	if [ "$?" != "0" ]; then
	    echo -e "${FAIL} ${MESSAGE}"
	    exit 1
	else
		echo -e "${GOOD} ${MESSAGE}"
	fi
}

# Output Version
function show_version {
	echo -e "${INFO} ${PROGRAM} ${VERSION}"
}

# SCRIPT EXECUTION ###########################

show_version
	
	MESSAGE="Evaluating Script Arguments"
	echo -e "${STAT} ${MESSAGE}"

case $# in
	
	0)
		echo -e "${FAIL} ${MESSAGE}"
			list_gs_arguments
	;;
	
	1)
   		case $1 in
   	 		pull)
				echo -e "${GOOD} ${MESSAGE}"
				
				MESSAGE="Pull Requested"
				echo -e "${STAT} ${MESSAGE}"
					import_gs

				echo -e "[${CYAN}STAT${NC}] Validating Folder Configuration"
					validate_gs_folders
					validate_ph_folders
					
				pull_gs
				exit
 			;;

			push)	
				echo -e "[${GREEN}GOOD${NC}] Push Requested"
					import_gs

				echo -e "[${CYAN}STAT${NC}] Validating Folder Configuration"
					validate_gs_folders
					validate_ph_folders
					
				push_gs
				exit
			;;
	
			version)
				show_version
				exit_nochange
			;;
	
			update)
				echo -e "[${GREEN}GOOD${NC}] Update Requested"
					update_gs
				exit_nochange
			;;
	
			logs)
				MESSAGE="Logs Requested"
				echo -e "${GOOD} ${MESSAGE}"
					logs_gs
			;;
			
			cron)
				CRONPATH="$HOME/${LOCAL_FOLDR}/${CRONJOB_LOG}"
				
				MESSAGE="Replaying Last Cronjob"
				echo -e "${STAT} ${MESSAGE}"
				
				if [ -f ${CRONPATH} ]
				then
					if [ -s ${CRONPATH} ]
						echo -e "${GOOD} ${MESSAGE}"
							logs_crontab
							exit_nochange
					then
						echo -e "${FAIL} ${MESSAGE}"
						echo -e "${YELLOW}${CRONPATH}${NC} appears empty"
							exit_nochange
					fi
				else
					echo -e "${FAIL} ${MESSAGE}"
					echo -e "${YELLOW}${CRONPATH}${NC} cannot be located"
						exit_nochange
				fi
				
			;;

			*)
				MESSAGE="'${YELLOW}$1${NC}' is an Invalid Argument"
				echo -e "${FAIL} ${MESSAGE}"
        			list_gs_arguments
					exit_nochange
			;;
		esac
	;;
	
	*)
		MESSAGE="Too Many Arguments"
		echo -e "${FAIL} ${MESSAGE}"
			list_gs_arguments
			exit_nochange
	;;
esac