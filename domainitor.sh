#!/bin/bash

# Clean up temporary files on exit.
function cleanup {
	[[ -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR" # Recursively remove temporary directories and files.
	kill 0 # Kill group processes (parent process and child processes.)
}

trap exit HUP INT QUIT TERM  # Trap HUP, INT, QUIT, and TERM signals to execute the exit command.
trap cleanup EXIT # Trap the exit command to execute the cleanup function.

# License
echo "
Licensed under a Creative Commons Attribution-ShareAlike 4.0
© 2021 By Omokolade Ogunleye"

# Program arguments management.
USAGE="\nUsage: ./domainitor.sh [-c] [n] [-f] [path/to/list]\n\n
\tAutomates mass-generation of domain names expiry report.\n\n
\tOutputs the result of each domain name in the supplied list to standard\n
\toutput and generates a report file when the program finish running.\n\n
\tOptions:\n
\t\t-c\tset n concurrency rate, n ranges from 2 to 32; default is 5\n
\t\t-f\trelative or absolute path to the list containing domain names\n
\t\t\tto check\n\n
\tExit Status:\n
\tReturns success unless interruption or an error occurs.\n\n" # Store usage info to out to standard output when a user supplies an invalid argument.

while getopts ":c:f:" arg # getopts function with a while loop to read the program argument options and values.
do
	case $arg in # Case statement to match the particular option and store the argument value in a variable.
		c) CONCURRENCY=$OPTARG;;
		f) DOMAIN_LIST=$OPTARG;;
		*) echo -en $USAGE >&2
		   exit 1 ;;
	esac

	[[ ( "$arg" =~ c && "$OPTARG" =~ ^[2-9]$|^[1-2]+[0-9]$|^3+[0-2]$ ) || ( "$arg" =~ f && "$OPTARG" =~ ^[a-zA-Z0-9~/_\.{3,255}(\-)]*[a-zA-Z0-9_~\.(\-)]$ ) ]] && continue || echo "$USAGE" && exit 1 # Check if all supplied argument options and values are valid.
done

[[ -z "$CONCURRENCY" ]] && CONCURRENCY=5 # Check if the user-supplied concurrency argument option value is valid. Else default to 5.

# Check for the program dependencies readiness.
echo -e "\n[DEPENDENCIES] Checks to verify if dependencies are OK and ready to go!\n"
echo -e "This program assumes your systems run Bash or similar shell with the APT
package manager.\n"

for package in grep whois sed # Loop through the list of program dependencies.
do
	if ! type $package > /dev/null 2>&1 # Check if already installed all the dependencies: grep whois sed.
	then # Do this if there is any missing dependency.
		MISSING_DEP="$package " # Store missing dependencies in a variable.
	fi
done

if [[ -z $MISSING_DEP ]] # Check if there is any missing dependency added to the variable $MISSING_DEP.
then # Do this if there aren't missing dependencies.
	echo "[OK] Dependencies are ready!"
else # Do this if there are missing dependencies.
	echo -e "[ERROR] Missing dependencies!\n"
	echo -e "The following dependencies are missing: $MISSING_DEP\n"
	read -rp "To install missing dependencies and continue running this program enter Y|y or N|n to quit: " INSTALL_DEP
	while [[ -z $INSTALL_DEP || $INSTALL_DEP =~ [^YNyn] ]] # Create a loop to prompt for the installation of dependencies if the user supplied the wrong input.
	do
		echo -e "\nYour input is invalid. Please try again.\n"
		read -rp "To install missing dependencies and continue running this program enter Y|y or N|n to quit: " INSTALL_DEP
	done
	if [[ $INSTALL_DEP =~ [YNyn] ]] # Confirm that the user input for the prompt to install dependencies is valid.
	then
		if [[ $INSTALL_DEP =~ [Yy] ]] # Check if the user chose to install dependencies.
		then
			echo -e "\r"
			echo -e "If you're not a root user, you may have to belong to the sudoer group and supply your password to install dependencies.\n"
			sleep 10s
			if sudo apt update && sudo apt install $MISSING_DEP # Check if the update of the package repo and installation of the missing dependencies are successful.
			then
				echo -e "\n[OK] Dependencies are ready!"
			else # Do this if the installation of missing dependencies failed.
				echo -e "\n[ERROR] The program could not install critical dependency!\n"
				exit 126
			fi
		else # Do this if the program could not install a critical dependency.
			echo -e "\r"
			exit 126
		fi
	fi
fi

# Here we collect the domains to check by the user providing the path to the list.
if [[ -z "$DOMAIN_LIST" ]]
then # Do this if a user didn't initially supply a list using the -f option.
	echo -e "\r"
	read -rp "Specify by entering the relative or absolute path to the list of domains to 
check: " DOMAIN_LIST # Accept user's input, i.e., the path to the domain names list.
fi

while [[ -z $DOMAIN_LIST || ! -s $DOMAIN_LIST  ]] # Recursive while loop to check if the provided list is valid.
do
	if [[ -n $DOMAIN_LIST && -s $DOMAIN_LIST ]] # Check if the provided list path is valid.
	then # Do this if the list path is valid.
		break
	elif [[ -z $DOMAIN_LIST ]]
	then # Do this if the list name isn't valid.
		echo -e "\n[ERROR] A valid domain list is required!"
		read -rp "Specify a valid relative or absolute path to the list of domains to check: " DOMAIN_LIST # Accept user's input, i.e., the path to the domain names list.
	elif [[ ! -s $DOMAIN_LIST ]]
	then # Do this if the list file is empty or doesn't exist.
		echo -e "\n[ERROR] Domain list supplied may be invalid, empty or doesn't exist!"
		read -rp "Specify by entering the relative or absolute path to the list of domains to 
check: " DOMAIN_LIST # Accept user's input, i.e., the path to the domain names list.
	fi
done

# Building report.
if [[ $( ping -qc 1 -W 1 8.8.8.8 | grep -c "1 received" ) -eq 1 ]] # Check if there's internet connectivity.
then # Do this if there's internet connectivity.
	TMP_DIR=/tmp/domain_expiry_report_$$_$( date +%Y-%m-%d_%H:%M:%S ) && mkdir -p "$TMP_DIR/whois/" "$TMP_DIR/reports/" # Create temporary directories.
	TMP_WHOIS_FILE=$TMP_DIR/whois/whois # Initial temporary WHOIS file.
	TMP_REPORT_FILE=$TMP_DIR/reports/report # Initial temporary report file.
	REPORT_FILE=domain_expiry_report_$( date +%Y-%m-%d_%H:%M:%S ).csv # Here is the file where the program store the report. The file is moment-based.
	SN=1 # Loop counter.
	echo -e "\r"
	echo -e "Domain Expiry Report for $( date "+%A %B %d %Y" ) at $( date "+%H:%M" )\n" | tee -a "$TMP_REPORT_FILE" # The report title.
	echo "SN, Domain Name, Expiry Date, Registrar, Status" | tee -a "$TMP_REPORT_FILE" # The header of the report.
	while read -r line # Loop through the domain names list.
	do ( # Start of a subshell.
		while grep -Poq "^((?!-)(?!.*-{2,})[a-zA-Z0-9-ßàÁâãóôþüúðæåïçèõöÿýòäœêëìíøùîûñé]{2,63}(?<!-))\.+[a-zA-Z]{2,63}(\.[a-zA-Z]{2,63})?$" <<< "$line" # Loop recursively as long as the current line in the supplied domain names list matches a valid format.
		do
			if [[ $( whois -H "$line" > "$TMP_WHOIS_FILE-$line-$SN" 2>&1 ) || "$?" =~ ^[01]$ ]] # Check if getting the WHOIS data is successful and redirected to a file.
			then # Do this if the recovery of the WHOIS data is successful and temporarily stored.
				EXP_DATE=$( ( grep -Eim 1 'Expiry|paid-till|Expires on|expire:' "$TMP_WHOIS_FILE-$line-$SN" | sed 's/\//-/g' || echo "NA" ) | grep -Po '\d[^\s]*' | head -1 | cut -d "T" -f 1 ) # Determine the corresponding domain name's expiry date.
				sed -z 's/\n/, /' <<< "$SN, $line" > "$TMP_REPORT_FILE-$line-$SN" # Determine the SN and the name for the respective domain and store temporarily.
				sed -z 's/\n/, /' <<< "$EXP_DATE" >> "$TMP_REPORT_FILE-$line-$SN" # Extract the corresponding domain name's expiry date from temporarily stored WHOIS data and append it to the temporary file from the step above.
				( grep -im 1 "Registrar:" "$TMP_WHOIS_FILE-$line-$SN" || echo "NA" ) | cut -d ":" -f 2 | sed -e 's/^[ \t]*//' | tr -d "," | sed -z 's/\n/, /' >> "$TMP_REPORT_FILE-$line-$SN" # Extract the corresponding domain name's registrar name from temporarily stored WHOIS data and append it to the temporary file from the step above.
				ABT_TO_EXP=3024000 # The total number of seconds in 5 weeks (to check if a domain name is about to expire.)
				if [[ "$EXP_DATE" =~ ^([0-9]{4})-(0[1-9]|1+[0-2])-(0[1-9]|[1-2]+[0-9]|3+[0-1])$ ]] # Check if the domain name expiry date is not empty and is valid.
				then # Do this if the domain name expiry date is not empty and is valid (to determine the expiry status of the corresponding domain.)
					VALIDITY=$(( $( date -d "$EXP_DATE" +%s ) - $( date +%s ) )) # Determine the corresponding domain name validity.
					if [[ "$VALIDITY" -lt 0 ]] # Check if the corresponding domain name has expired.
					then # Do this if the corresponding domain name has expired.
						echo "Expired" | tr -d "\n" >> "$TMP_REPORT_FILE-$line-$SN"						
					else # Do this if the corresponding domain name hasn't expired.
						if [[ "$VALIDITY" -le "$ABT_TO_EXP" ]] # Check if the validity of the corresponding domain name is precisely five weeks or within.
						then # Do this if the domain name is about to expire, i.e., precisely five weeks or within.
							echo "Active (Expiring Soon)" | tr -d "\n" >> "$TMP_REPORT_FILE-$line-$SN"
						else # Do this if the domain name expiry is beyond five weeks.
							echo "Active" | tr -d "\n" >> "$TMP_REPORT_FILE-$line-$SN"
						fi
					fi
				else # Do this if unable to determine the expiry status of the domain, i.e., empty or invalid.
					echo "NA" | tr -d "\n" >> "$TMP_REPORT_FILE-$line-$SN"
				fi
				echo -e "\r" >> "$TMP_REPORT_FILE-$line-$SN"
				cat "$TMP_REPORT_FILE-$line-$SN" | awk '{$1="*,"; print ;}' # Obscures the SN column as the program has not sorted the generated results yet.
				break # Exit while loop at this point.
			elif [[ $( ping -qc 1 -W 1 8.8.8.8 | grep -c "1 received" ) -ne 1 ]]
			then # Do this if the recovery of the WHOIS data failed due to internet connectivity.
				echo "[ERROR] => There's an interruption due to the loss of internet connectivity.
Reconnecting ..." 
				continue # Continue the "while true" loop.
			fi
		done
	) 2> /dev/null & # End of a subshell.
		while [[ $( jobs | grep -c "Running" ) -ge "$CONCURRENCY" ]]; do continue; if [[ $( jobs | grep -c "Running" ) -lt "$CONCURRENCY" ]]; then break; fi done # Concurrency management.
		[[ -n $line ]] && (( SN++ )) # Execute loop counter increment if the current line in the supplied domain names list is not empty.
	done < "$DOMAIN_LIST" # Redirect the domain names list for the loop to read.
	wait # Wait for all currently running (subshell) jobs to finish.
	CHECKED_DOMAINS=$( find "$TMP_DIR/reports/" -iname "report-$line*" | wc -l ) # Determine the value of all checked domain names.
	if [[ "$CHECKED_DOMAINS" -ge 1 ]] # Check if there are reports to generate.
	then # Do this if there are reports to generate (put together all results, create report statistics, and create the report file.)
		cat "$TMP_REPORT_FILE" > "$REPORT_FILE" && cat "$TMP_REPORT_FILE"-"$line"* | sort -n >> "$REPORT_FILE" # Concatenate report title, header, and individual domain result.
		UNSUCCESSFULLY_CHECKED=$( grep -c $', NA\r' "$REPORT_FILE" ) # Determine the value of unsuccessfully checked domain names.
		SUCCESSFULLY_CHECKED=$(( CHECKED_DOMAINS-UNSUCCESSFULLY_CHECKED )) # Determine the value of successfully checked domain names.
		EXP_SOON=$( grep -c $', Active (Expiring Soon)\r' "$REPORT_FILE" ) # Determine the value of the domain names that are about to expire.
		echo -e "\nTotal no of CHECKED domain(s): $CHECKED_DOMAINS" | tee -a "$REPORT_FILE"
		echo "Total no of SUCCESSFULLY CHECKED domain(s): $SUCCESSFULLY_CHECKED" | tee -a "$REPORT_FILE"
		echo "Total no of UNSUCCESSFULLY CHECKED domain(s): $UNSUCCESSFULLY_CHECKED" | tee -a "$REPORT_FILE"
		echo "Total no of EXPIRED domain(s): $( grep -c $', Expired\r' "$REPORT_FILE" )" | tee -a "$REPORT_FILE"
		echo "Total no of ABOUT TO EXPIRE domain(s): $EXP_SOON" | tee -a "$REPORT_FILE"
		echo "Total no of ACTIVE domain(s): $( grep -Ec ", Active+( (Expiring Soon))?" "$REPORT_FILE" ) $( [[ "$EXP_SOON" -gt 0 ]] && echo "($EXP_SOON Expiring Soon)" )" | tee -a "$REPORT_FILE" 
		echo -e "\n[DONE] Report file: $( pwd )/$REPORT_FILE"
	else # Do this if the program fails to generate report.
		echo -e "\n[DONE] There's no report to generate! Check if your domain names list is 
valid and not empty." | tee -a "$REPORT_FILE"
	fi
else # Do this if there's no internet connectivity.
	echo -e "\n[ERROR] Check your internet connectivity and try again!"
fi
