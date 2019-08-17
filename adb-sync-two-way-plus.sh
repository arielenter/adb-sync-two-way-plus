#!/bin/bash
################## Functions declaration ######################
################## Error Handler #############
trap "exit 1" TERM
export TOP_PID=$$
let_me_handle_it=""
error() {
	if [ "$let_me_handle_it" == "" ];then
		local parent_lineno="$1"
		local message="$2"
		local code="${3:-1}"
		if [[ -n "$message" ]] ; then
			message="Error on or near line ${parent_lineno}: ${message}; exiting with status ${code}"
		else
			message="Error on or near line ${parent_lineno}; exiting with status ${code}"
		fi
    echo "UNEXPECTED HAS OCCUR ERROR: $message"
  	if [ -n "$use_zenity" ];then
  			zenity --error --no-markup --text "An unexpected error has ocurre:

$message"
    fi
		exit "${code}"
	fi
}
trap 'error ${LINENO}' ERR
function finish {
  if [ -f .tmp_sync_file ];then rm .tmp_sync_file; fi
}
trap finish EXIT
##############################################
function error_this {
	(>&2 echo "ERROR: $1") #echo to stderr
	[ "$2" == "1" ] && echo "$usage"
	if [ -n "$use_zenity" ];then
		lines=$(echo "$1" | wc -l)
		if [ "$lines" -gt "2" ];then #use a text-info instead of a question dialog if the list of files it's too long
			zenity --text-info --title="Error" --window-icon=error --no-markup --width=500 --height=500 --filename=<(echo "$1")
		else
			zenity --error --no-markup --text "$1" --width=500
		fi
	fi
  if [ "$3" != "1" ];then
    	sync_canceled
  fi
}
function info_this {
    echo "$1"$'\n'$'\n'"$2"
    if [ -n "$notify" ];then
        notify-send "$1" "$2" -t 4000 -i emblem-default
    else
        if [ -n "$use_zenity" ];then
            [[ $something_done == true ]] && sleep 1
            zenity --info --text "$1"$'\n'$'\n'"$2"
        fi
    fi
}
function alert_this {
	if [ -n "$use_zenity" ];then
		lines=$(echo "$1" | wc -l)
		if [ "$lines" -gt "30" ];then #use a text-info instead of a question dialog if the list of files it's too long
			zenity --text-info --title="Do you want to continue anyway?" --window-icon=question --no-markup --width=500 --height=500 --ok-label "Yes" --cancel-label "No" --filename=<(echo "$1")
		else
			zenity --question --title="Do you want to continue anyway?" --ok-label "Yes" --cancel-label "No" --no-markup --text "$1"
		fi
		if ! [ "$?" -eq "0" ];then
			sync_canceled
		fi
	else
		read -p "$1"' Type "Y" or "y" for "Yes". Anything else will be "No": ' -n 1 -r
		echo ""
		if ! [[ "$REPLY" =~ ^[Yy]$ ]];then
			sync_canceled
		fi
	fi
}
function sync_canceled {
	message="Sync has been canceled. No changes were made."
	echo "WARNING: $message"
	if [ -n "$use_zenity" ];then
		zenity --warning --no-markup --text "$message"
	fi
	exit
}
function canceled_before_finished {
	message="Sync has been canceled before it was completely finished. Keep in mind that the inventory log won't be updated until you do. This means that “deleted” detection won't be available for all new files that were pushed or pulled in the middle of the process until you completely finish the synchronization again. Until then, if you deleted one of them in one side but you keep it in the other, it will be threated as a new file and not as deleted one."
    message=$message$'\n'$'\n'"Also, you might need to run sudo 'adb kill-server' and 'sudo adb start-server' before you can use this script again to avoit having to restat both devices to do so."
	echo "WARNING: $message"
	if [ -n "$use_zenity" ];then
		zenity --warning --no-markup --text "$message" --width=600
	fi
    kill -s TERM $TOP_PID
}
function ask_question {
	if [ -n "$use_zenity" ];then
		lines=$(echo "$1" | wc -l)
		if [ "$lines" -gt "30" ];then #use a text-info instead of a question dialog if the list of files it's too long
			zenity --text-info --title="Please choose Yes or No" --window-icon=question --no-markup --width=500 --height=500 --ok-label "Yes" --cancel-label "No" --filename=<(echo "$1")
		else
			zenity --question --title="Please choose Yes or No" --ok-label "Yes" --cancel-label "No" --no-markup --text "$1"
		fi
		if [ "$?" -eq "0" ];then
			answered='TRUE'
		else
			answered='FALSE'
		fi
	else
		read -p "$1"' Type "Y" or "y" for "Yes". Anything else will be "No": ' -n 1 -r
		if [[ "$REPLY" =~ ^[Yy]$ ]];then
			answered='TRUE'
		else
			answered='FALSE'
		fi
		echo ""
	fi
}
answer=""
function ask_list {
	number=0
	values=""
	while read -r; do
		let "number++"
		values+="$number|$REPLY"$'\n'
	done <<< "$2"
	if [ -n "$use_zenity" ];then
		columns_names=$(echo "$1" | sed "s,|,\n,g")
		columns='--column="" --column=""'
		while read -r line; do
			columns+=" --column=\"$line\""
		done <<< "$columns_names"
		values=$(echo "$values" | sed 's/^/\|/g' | sed "s,|,\n,g")
		values="TRUE"$values
		choice=$(echo "$values" | eval "zenity --window-icon=question --no-markup --list --title=\"$3\" --text='$4' --radiolist --print-column='ALL' --hide-column=\"2\" --width=800 --height=500 $columns")
		if [ -z "$choice" ];then
			sync_canceled
		fi
		answer="$choice"
	else
		echo "WARNING: $3"
		echo "$4"$'\n'
		list=$(echo "Option"$'\t'"$1" | sed "s,|,    \t,g")$'\n'
		list+=$(echo "$values" | sed "s,|,  \t,g")$'\n'
		echo "$list"
		while true; do
			read -p "Type down the option number and then hit enter. Type \"C\" to cancel: " </dev/tty
			case "$REPLY" in
				[Cc])
					sync_canceled
				;;
				''|*[!0-9]*)
					echo $'\n'"ERROR: '$REPLY' is not a valid option number. Please chose an option number from the list."
				;;
				*)
					if [ "$REPLY" -le "$number" ] && [ "$REPLY" -ge "1" ];then
						break
					else
						echo $'\n'"ERROR: '$REPLY' is not an available option number. Please chose an option number from the list."
					fi
				;;
			esac
			echo $'\n'"$list"
		done
		answer=$(echo "$values" | sed -n "$REPLY"p)
	fi
}
function run_with_su {
	if [ $do_not_use_su = "false" ];then
		answered=""
		do_not_use_su=true
		do_it=true
		while $do_it;do
			do_it=false
			start=`date +%s`
			su_output=$(eval "$adb_su""$1""\'' echo \|\|OK;'\'") </dev/tty
			end=`date +%s`
			runtime=$((end-start))
			su_output=$(echo "$su_output" | tr -d "\r")
			su_output1=$(echo "$su_output" | tail -n1)
			su_output2=$(echo "$su_output" | sed '$ d' | tail -n1)
			if [ "$su_output1" != "||OK" ];then
				if [ "$runtime" -gt 4 ];then
					ask_question "It appears that your device might be able to use “adb shell su”, but you need to see your device's screen and accept it.

Although “adb shell su” is not absolutely necessary for this script to work, it is very much recommended to better keep files' date/time stamps accurate.

Would you like me to try to use “adb shell su” again? Then say “yes” and put attention on your device's screen to accept it. Other wise, say “no” and the script will continue working without “adb shell su”.

To stop this question from being ask every time, you may use option '-n' to work always without “adb shell su”. Also, I recommend you allow this permanently on your device screen, or at least for enough time for this script to end the job, so that you are not asked every time “adb shell su” needs to be executed."
					if [ "$answered" == "TRUE" ];then
						do_it=true
					fi
				fi
			else
				do_not_use_su=false
				answered="$su_output2"
			fi
		done
	fi
}
function update_android_date {
	if [ "$do_not_use_su" == "false" ];then
		file_name_escaped=$(echo "$file_name" | sed "s,','\\\\\'\\\\\\\\\\\\\'\\\\\\\\\\\\\\\\\\\\\\\\\\\\'\\\\\\\\\\\\\'\\\\\'',g")
		for do_it_twice in 1 2;do
			if [ "$touch_value" == "epoch" ];then
				date_to_use=$((epoch[2]-epoch_adjustment))
			else
				date_to_use=$(date "+%Y%m%d%H%M.%S" -d @$((epoch[2]-epoch_adjustment)))
			fi
			run_with_su "\''touch -m -a -t $date_to_use '\'\\\\\'\''$file_name_escaped'\'\\\\\'\''; stat '\'\\\\\'\''$file_name_escaped'\'\\\\\'\'' -c %Y;'\'" </dev/tty
			current_epoch="$answered"
			if ! [[ "$current_epoch" =~ ^-?[0-9]+$ ]];then
				current_epoch=0
				break
			fi
			[ "$current_epoch" -eq "${epoch[2]}" ] && break
			epoch_adjustment=$((current_epoch-epoch[2]))
		done
		if [ "$current_epoch" -ne "${epoch[2]}" ];then
			file_name_escaped=$(echo "$file_name" | sed "s,','\"'\"'\"'\"'\"'\"'\"'\"',g")
			current_epoch=$(eval "$adb_shell""'touch '\"'\"'$file_name_escaped'\"'\"'; stat '\"'\"'$file_name_escaped'\"'\"' -c %Y'" </dev/tty | tr -d "\r")
			current_date=$(date "+%Y%m%d%H%M.%S" -d @$((current_epoch)))
			touch -m -t $current_date "$file_name"
			do_not_use_su=true
			inventory_list+=$'\n'$(echo "${side[2]}" | cut -f1,2 -d "|")"|$current_epoch"
		else
			inventory_list+=$'\n'"${side[2]}"
		fi
	else
		if ! [[ "${epoch[1]}" =~ ^-?[0-9]+$ ]];then
			file_name_escaped=$(echo "$file_name" | sed "s,','\"'\"'\"'\"'\"'\"'\"'\"',g")
			epoch[1]=$(eval "$adb_shell""' stat '\"'\"'$file_name_escaped'\"'\"' -c %Y'" </dev/tty | tr -d "\r")
			side[1]=$(echo "${side[2]}" | cut -f1,2 -d "|")"|${epoch[1]}"
		fi
		date_var[1]=$(date "+%Y%m%d%H%M.%S" -d @$((epoch[1])))
		touch -m -t ${date_var[1]} "$file_name"
		inventory_list+=$'\n'"${side[1]}"
	fi
}
################## The script starts here ###################
################## Check arguments and requiarements before starting sync ######################
usage="USAGE: adb-sync-two-way-plus.sh Android_absolute_path Local_absolute_path [OPTIONAL Arguments]
NOTE: If no local directory is given, the current directory is used insted.
OPTIONAL Arguments:
   --help             Display this manual and exit ignoring
                      all other arguments and taking no accions.

   -h                 Include hidden files.

   -g                 Use zenity GTK+ (GUI) dialog boxes.

   -f                 Use notify-send to send a system notification when a
                      synchronization has successfully ended. This will also 
                      replace zenity's successful dialog box at the end if 
                      option “-g” is used in conjunction with this option.

   -m [4-8]           When modifications to a file are found from both the
                      android device and the local device, the user will be
                      prompt to choose what to do. This option can be used
                      to give an upfront answer so that the user won't be asked.
                      The possible answers are the following:
                      4 Always Keep both files by renaming the oldest adding
                        its modification date/time to its name.
                      5 Always keep the file with the newest modifications.
                      6 Always keep the old one instead.
                      7 Always keep the local version.
                      8 Always keep the android version.

   -d [3-6]           When a file has been deleted in one side and modified in
                      the other, the user will be prompt to choose what to do.
                      This option can be used to give an upfront answer so that
                      the user won't be asked. The possible answers are the
                      following:
                      3 Always delete the file
                      4 Always keep the file if modifications were made
                      5 Always prioritize and choose the local operation
                      6 Always prioritize and choose the android operation

   -a [adb_path]           Specifie the adb binary that will be used.
                           This is useful if your system is not including 
                           adb on its environment or shell variables, or
                           if you want to use a different version of adb
                           than the one installed in your system.

   -s [Android_serial]     If multiple android devices are connected, this
                           option can be added to specify witch one to use,
                           otherwise the user will be prompt to choose one
                           from a list of available devices.

   -n                 The script won't check if your device is rooted and there
                      for capable of using “adb shell su”. “adb shell su” is 
                      used to better keep time/date file stamps accurate, but
                      its used is not absolutely necessary for this script to
                      work, just recommended.

   -r                 “adb root” would be run so that adb gains root access on
                      your device. This is useful if your android doesn't allow
                      any “adb push” to any directory at all without root. Also
                      it will allow “push -a”, which will help better keep
                      files' date/time stamps accurate. “adb root” or “adb
                      shell su” are not absolutely necessary for this script to
                      work but it is very much recommended. Unfortunately “adb
                      root” is not always available in all devices.

    -t                When files or directories are going to be deleted on your
                      local device because they were deleted on your android
                      device, this script will usually try send them to your
                      system trash bin using command “gvfs-trash”. If instead
                      you will like this elements to be permanently deleted,
                      you can use this option so that command “rm” is used.
                      This is also helpful if “gvfs-trash” is not available on
                      your system and installing it it's not an option.

    -p                This option can be used to prevent zenity's progress
                      dialog boxes from appearing even if option “-g” is given."
if [ "$#" -eq 0 ];then
	error_this "No argument given. Please provide at least the android path of the directory that is going to be sync." "1"
fi
look_for=' ./ \( ! -path "./" ! -path "/.*" ! -name ".*" \) -a \( -type f -or -type d \)'
adb="adb"
attribute=""
do_not_use_su=false
for i do
	if [ "$attribute" == "" ];then	
		case "$i" in
			/*)
				if [ -z "${path[1]}" ];then
					path[1]="$i"
					if [[ $(echo "${path[1]}" | sed ':a;N;$!ba;s,\n,[\:NPC\:],g' | egrep -e ' /| $|\[\:NPC\:\]|[[:cntrl:]]|<|>|\*|:|"|\?|\\' -e '\|') ]];then
						error_this "The android directory name can't contain any of the following characters: <, >, *, :, \", \, ?, |, and Non Printable Characters [:NPC:] other than space, like new lines and tabs for example. Also names can't end with a space." "1"
					fi
					path_escaped[1]=$(echo "${path[1]}" | sed "s,','\"'\"'\"'\"'\"'\"'\"'\"',g") #escape single quote (') which will be pass to adb
				else
					if [ -z "${path[2]}" ];then
						path[2]="$i"
					else
						other_paths+="'$i' "
					fi
				fi
			;;
			"-h")
				look_for='./ \( ! -path "./" ! -name ".tmp_sync_file" ! -name ".sync_inventory.log*" \) -a \( -type f -or -type d \)'
			;;
			"-n")
				do_not_use_su=true
			;;
			"-g")
				let_me_handle_it="TRUE"
				if ! hash zenity 2>/dev/null;then
					error_this "Zenity (GTK+) doesn't seem to be installed on your system. Please install it or remove the -g option to use terminal messages instead. Then run this script again." "1"
				fi
				let_me_handle_it=""
				use_zenity='TRUE'
			;;
			"-f")
				let_me_handle_it="TRUE"
				if ! hash notify-send 2>/dev/null;then
					error_this "'notify-send' doesn't seem to be installed on your system. Please install it or remove the -f option to get terminal notifications instead. After that, please run this script again." "1"
				fi
				let_me_handle_it=""
				notify='TRUE'
			;;
			"-p")
				  no_progress_bars='TRUE'
			;;
			"-t")
				dont_use_trash='TRUE'
			;;
			"-r")
				try_adb_root=true
			;;
			"--help")
				echo "$usage"
				exit
			;;
			-[samd])
				attribute="$i"
			;;
			*)
				error_this "'$i' is not recognized as a valid argument or an absolute path." "1"
			;;
		esac
	else
		[[ "$i" == -? ]] && error_this "I was expecting a value for attribute '$attribute', but instead I found another attribute '$i'. Attribute '$attribute' can not be given alone without a value." "1"
		case "$attribute" in
			-s)
				serial[1]="$i"
			;;
			-a)
				adb="$i"
			;;
			-m)
				if [[ "$i" != [4-8] ]];then
					error_this "Attribute '-m' can only accept numbers from 4 to 8, but istead value '$i' was given." "1"
				fi
				mod_vs_mod="$i"
			;;
			-d)
				if [[ "$i" != [3-6] ]];then
					error_this "Attribute '-d' can only accept numbers from 3 to 6, but istead value '$i' was given." "1"
				fi
				mod_vs_del="$i"
			;;
		esac
		attribute=""
	fi
done
if [ -z "$no_progress_bars" ] && [ -n "$use_zenity" ];then
	if ! hash unbuffer 2>/dev/null;then
		error_this "Command 'unbuffer' doesn't seem to be installed on your system. 'unbuffer' is essential to use ‘Zenity’ progress dialogs. Please install it or either remove the -g option or add the -p so that no progress dialogs are used and terminal messages are instead. Then run this script again." "1"
	fi
fi
[ "$attribute" != "" ] && error_this "I was expecting a value for attribute '$attribute', but instead I found nothing. Attribute '$attribute' can not be given alone without a value." "1"
[ -z "${path[1]}" ] && error_this "Please provide at least the android path of the directory that is going to be sync." "1"
[ -n "$other_paths" ] && alert_this "It appears that more than two absolute path were given. Only the first two ('${path[1]}' & '${path[2]}') will be used as the android and local paths respectively. The following paths will be ignore: $other_paths

Do you want to continue?"
let_me_handle_it="TRUE"
if ! hash gvfs-trash 2>/dev/null;then
	error_this "“gvfs-trash“ doesn't seem to be installed on your system. “gvfs-trash“ is used to move deleted elements to your local's system trash bin. If installing it is not an option or if you prefer for them to be deleted permanently from the get go instead, please used option “-p”." "1"
fi
let_me_handle_it=""
if [ "$adb" == "adb" ];then
	let_me_handle_it="TRUE"
	if ! hash $adb 2>/dev/null;then
		error_this "Couldn't find Android Debug Bridge installed on your system. It may not have been included on the environment or shell variables. You can specify its location with option \"-a\" if thats the case."
	fi
	let_me_handle_it=""
else
	if ! [[ -x "$adb" ]]; then
		error_this "Couldn't find '$adb'. Please make sure you are giving the right location and that it has execute permission."
	else
		if ! [[ $("$adb" version | grep "Android Debug Bridge") ]]; then
			error_this "The file given ('$adb') doesn't apper to be a valid Android Debug Bridge executable."
		fi
	fi
fi
"$adb" start-server
list[1]=$("$adb" devices -l | sed '1d; $d; s/^ *//')
if [ "${list[1]}" == "" ];then
	error_this "No Android found. Make sure the android device is properly connected and that you have enabled Android Debugging Bridge on it, then try again."
fi
if ! [ -n "${serial[1]}" ];then
	list[1]=$(echo "${list[1]}" | sed "s, \+,\|,")
	if [ $(echo "${list[1]}" | wc -l) -gt "1" ];then
		ask_list "Serial Number|Info" "${list[1]}" "Select the Android device you will like to sync" "More than one Android device is connected. Which one would you like to use?"$'\n'"Note: you can skip this question by giving it's serial number using option -s of adb-sync-two-way-plus."
		serial[1]=$(echo "$answer" | cut -f2 -d "|")
	else
		serial[1]=$(echo "${list[1]}" | cut -f1 -d "|")
	fi
fi
adb_escaped=$(echo "$adb" | sed "s,','\"'\"',g")
serial_escaped[1]=$(echo "${serial[1]}" | sed "s,','\"'\"',g")
adb_escaped="'$adb_escaped' -s '${serial_escaped[1]}'"
let_me_handle_it="TRUE"
state[1]=$(eval "$adb_escaped get-state" 2>&1)
if [ $? -ne 0 ];then
	case "${state[1]}" in
		*"not found"*)
			error_this "Couldn't find the android device given ('${serial[1]}'), I did find some other device/s connected though. If you want to use it/them instead, run this script again without the -s option. Otherwise, Make sure you are giving its right serial number, that it is properly connected, and that you have enabled Android Debugging Bridge on it. Then try again."
		;;
		*"unauthorized"*)
			error_this "Adb access hasn't been authorized on your android device. Check your android's screen to allow the adb connection. Then run this script again. If you keep having problems, use the following command to try to troubleshot the problem and seek for help on the Internet:"$'\n'$'\n'"adb devices"
		;;
		*)
			error_this "Adb is reporting the following when trying to get your device's status:"$'\n'$'\n'"${state[1]}"$'\n'$'\n'"Run the following command on terminal to troubleshot the problem and seek for help on the Internet:"$'\n'$'\n'"adb devices"
		;;
	esac
fi
let_me_handle_it=""
if [ "$try_adb_root" == "true" ];then
	adb_root=$(eval "$adb_escaped root")
	if ([ "$adb_root" != "restarting adbd as root" ] && [ "$adb_root" != "adbd is already running as root" ]);then
		alert_this "Adb returned the following error when executing “adb root”:

$adb_root

“adb root” might not be available for your device. “adb root” is not absolutely necessary for this script to work and “adb shell su” might be tried and used instead. “adb root” or “adb shell su” are not necessary, but they are very much recommended to keep files' date/time stamps accurate.

Would you like to continue and try to use “adb shell su”?"
	fi
fi
adb_shell="$adb_escaped shell 'cd '\"'\"'${path_escaped[1]}'\"'\"';'"
test_directory=$(eval "$adb_shell""'[ \$? -eq 0 ] && echo \"||OK\"'")
if [[ "$test_directory" != *"||OK"* ]];then
	case "$test_directory" in
		*":"*"Permission denied"*)
			error_this "It seems that adb doesn't have enough permission to access the Android directory given (\"${path[1]}\") without root. You may use option “-r” witch would run adb as root if “adb root” is available for your device, but I wouldn't recommend you do that yet.

Usually root only directories may contain sensitive data that may harm your android system if you made incorrect changes to it.

Try to find other directories that adb can use without root. For instance, with the following command I was able to find out that my external sdcard was located in /storage/DC27-7413 which was read/writable by adb without root:

adb shell df

Unfortunately, there are some devices where “adb push” won't be able to send any files to any destination at all, and where “adb root” may not be available. If this is your case, try to look on the Internet for ways to allow “adb push” to work on your device, most probably by using “adb shell su” to mount a directory with read/write permission for adb, or ways to be able to run “adb root” on a production build."
		;;
		*":"*"No such file or directory"*)
			error_this "The Android directory given (\"${path[1]}\") doesn't exist in the android device. Please make the directory before proceeding or make sure you are giving the right path in the correct order."
		;;
		*)
			error_this "Adb return the following error when trying to gain access to Android directory given (\"${path[1]}\"):

$test_directory

Please make sure you are giving the right path in the correct order and the directory actually exist."
		;;
	esac
fi
[[ $(eval "$adb_shell""' if ! [ -w './' ];then echo 'TRUE'; fi'") ]] && error_this "It seems that adb doesn't have write permission for the Android directory given (\"${path[1]}\") without root. You may use option “-r” witch would run adb as root if “adb root” is available for your device, but I wouldn't recommend you do that yet.

Usually root only directories may contain sensitive data that may harm your system if you made changes to it.

Try to find other directories that adb can use without root. For instance, with the following command I was able to find out that my external sdcard was located in /storage/DC27-7413 which was read/writable by adb without root:

adb shell df

Unfortunately, there are some devices where “adb push” won't be able to send any files to any destination at all, and where “adb root” may not be available. If this is your case, try to look on the Internet for ways to allow “adb push” to work on your device, most probably by using “adb shell su” to mount a directory with read/write permission for adb, or ways to be able to run “adb root” on a production build."
if [ -z "${path[2]}" ];then
	alert_this "No local directory given. Are you sure you want to use the current directory ('$PWD')?"
	path[2]="$PWD"
fi
path_escaped[1]=$(echo "${path[1]}" | sed "s,','\\\\\'\\\\\\\\\\\\\'\\\\\\\\\\\\\\\\\\\\\\\\\\\\'\\\\\\\\\\\\\'\\\\\'',g")
adb_su="$adb_escaped shell 'su -c '\''cd '\'\\\\\'\''${path_escaped[1]}'\'\\\\\'\'';'\'"
echo "Checking if “adb shell su” is available on your device. Please check your device's screen for any warning. This might take a few seconds..."
run_with_su >/dev/null
! ([ -w "${path[2]}" ] && [ -r "${path[2]}" ]) && error_this "The local directory given ('${path[2]}') doesn't exist, or if it does, you don't have the right permissions to read nor/or to write on it. Please make sure you are giving the right path in the correct order and that you have read/write permissions for it."
cd "${path[2]}"
echo "Done. Now working on your sync..."
################## Get local tree separating files from directories and discarding the ones with invalid names for android ################
let_me_handle_it="TRUE"
do[2]=$(eval "find $look_for -print0 2>/dev/null" | sed ':a;N;$!ba;s,\n,\[\:NPC\:\],g' | tr '\000' '\n' | sed 's,[[:cntrl:]],\[\:NPC\:\],g') #NPC is my way of pointing out Non Printable Character
let_me_handle_it=""
if [ "${do[2]}" != "" ];then
  while read -r; do
	  if [[ $(echo "$REPLY" | egrep -e ' /| $|\[\:NPC\:\]|<|>|\*|:|"|\?|\\' -e '\|') ]];then 
		  if [[ ! $(echo "$REPLY" | egrep -e ' /|\[\:NPC\:\].*/|<.*/|>.*/|\*.*/|:.*/|".*/|\?.*/') ]];then #show only invalid parents, ignore their children
			  invalid_names+="$REPLY"$'\n'
		  fi
	  else
		  if (! [ -r "$REPLY" ] || ! [ -w "$REPLY" ]);then
			  [[ "$REPLY" != "$directory_no_rw/"* ]] && no_read_write[2]+="$REPLY"$'\n'
			  [ -d "$REPLY" ] && directory_no_rw="$REPLY"
		  else
			  if [ -d "$REPLY" ];then
				  list[2]+="$REPLY|Directory|"$'\n'
			  else
				  list[2]+=$(stat "$REPLY" -c '%n|%s|%Y|')$'\n'
			  fi
		  fi
	  fi
  done <<< "${do[2]}"
fi
if [ -n "$invalid_names" ];then
	message=$(echo "file or directory and its content won't be sync because it is")
	invalid_names=$(echo "$invalid_names" | sed '/^$/d' | sort)
	if [ $(echo "$invalid_names" | wc -l) -gt "1" ];then
		message=$(echo "files or/and directories and their content won't be sync because they are")
	fi
	alert_this "The following local $message using an invalid name for Android:

$invalid_names

The following characters can't be use on file/directory's names: <, >, *, :, \", \, ?, |, and Non Printable Characters [:NPC:] other than space, like new lines and tabs for example.
Also names can't end with a space.

Do you want to continue the synchronization without it or them?"
fi
if [ -n "${no_read_write[2]}" ];then
	message=$(echo "file or directory and its content won't be sync because you don't have read nor/or write permissions for it:")
	no_read_write[2]=$(echo "${no_read_write[2]}" | sed '/^$/d' | sort)
	if [ $(echo "${no_read_write[2]}" | wc -l) -gt "1" ];then
		message=$(echo "files or/and directories and their content won't be sync because you don't have read nor/or write permissions for them:")
	fi
	alert_this "The following local $message

${no_read_write[2]}

Do you want to continue the synchronization without it or them?"
fi
################## Get the Android tree ##################
list[1]=$(eval "$adb_shell"\'" find $look_for 2>&1"' | while read -r;do if ([ -w "$REPLY" ] && [ -r "$REPLY" ]);then if [ -d "$REPLY" ];then echo "$REPLY|Directory|";else stat "$REPLY" -c "%n|%s|%Y|" ;fi;else if [ "$REPLY" != "" ];then echo "$REPLY|Invalid|"; fi; fi;done'\')
list[1]=$(echo "${list[1]}" | tr -d "\r") #adb lines end both with \r and \n, but local terminal only ends with \n. I remove \r for comparation purposes
no_read_write[1]=$(echo "${list[1]}" | grep "|Invalid|$" | cut -f1 -d "|")
list[1]=$(echo "${list[1]}" | grep -v "|Invalid|$" | cat)
if [ "${no_read_write[1]}" ];then
	message=$(echo "file or directory and its content won't be sync because you don't have read nor/or write permissions for it:")
	no_read_write[1]=$(echo "${no_read_write[1]}" | sed '/^$/d' | sort)
	if [ $(echo "${no_read_write[1]}" | wc -l) -gt "1" ];then
		message=$(echo "files or/and directories and their content won't be sync because you don't have read nor/or write permissions for them:")
	fi
	alert_this "The following android $message

${no_read_write[1]}

Do you want to continue the synchronization without it or them?"
fi
################# Get previous tree inventory of files and directories #################
sync_inventory="./.sync_inventory.log"
if [ ! -f "$sync_inventory" ]; then
	touch "$sync_inventory"
fi
inventory_file=$(cat $sync_inventory)
path[1]=${path[1]%/}
not_the_same_device=false
if [ "$inventory_file" != "" ];then
	first_line=$(echo "$inventory_file" | head -n 1)
	if [ "$first_line" != "${serial[1]}|${path[1]}" ];then
      not_the_same_device=true
	fi
fi
inventory_file=$(echo "$inventory_file" | tail -n +2)
############### Exclude invalid files and directories from the lists ##################
for i in "y=1; x=2" "y=2; x=1";do
	eval "$i"
  if [ "${no_read_write[$y]}" ];then
	  while read -r; do
		  list[$x]=$(echo "${list[$x]}" | grep -F -v "$REPLY|" | cat)
		  inventory_file=$(echo "$inventory_file" | grep -F -v "$REPLY|" | cat)
	  done <<< "${no_read_write[$y]}"
  fi
done
################# Find if there is any file that shares its name with a directory in the other side ###############
file_dir_with_same_name=""
for i in "y=1; x=2" "y=2; x=1";do
  	eval "$i"
    list_of_directories=$(echo "${list[$y]}" | grep "Directory|$" | cut -f1 -d "|" | cat | sort)
    list_of_files=$(echo "${list[$x]}" | grep -v "|Directory|$" | cut -f1 -d "|" | cat | sort)
    file_dir_with_same_name+=$(comm -12 <(echo "$list_of_directories") <(echo "$list_of_files") | sed '/^$/d')$'\n'
done
file_dir_with_same_name=$(echo "$file_dir_with_same_name" | sed '/^$/d' | sort)
if [ -n "$file_dir_with_same_name" ];then
	message="The following name is"
	if [ $(echo "$file_dir_with_same_name" | wc -l) -gt "1" ];then
		message="The following names are"
	fi
	alert_this "$message shared by a file in one side and a directory in the other side at the same location. Since it is not possible to have a file and a directory with the same name in the same location, they and the files they contain will be excluded from the synchronization.

$file_dir_with_same_name

Do you want to continue the synchronization without them?"
  while read -r; do
    list[1]=$(echo "${list[1]}" | grep -F -v "$REPLY|" | cat)
    list[2]=$(echo "${list[2]}" | grep -F -v "$REPLY|" | cat)
    inventory_file=$(echo "$inventory_file" | grep -F -v "$REPLY|" | cat)
  done <<< "$file_dir_with_same_name"
fi
################ Compare current trees with the last sync inventory log to get modified, deleted and new state of files ####################
for it1 in 1 2;do
	inv_dif=$(comm <(echo "$inventory_file" | sort) <(echo "${list[$it1]}" | sort) | sed '/^$/d')
  list_untouch[$it1]="${list[$it1]}"
	mod[$it1]=$(echo "$inv_dif" | cut -s -f2 | sed "/^$/d")
  if [ "$not_the_same_device" == "false" ];then
      same[$it1]=$(echo "$inv_dif" | cut -s -f3 | sed "/^$/d")
  else
      same[$it1]=""
      mod[$it1]+='"$'\n'"'$(echo "$inv_dif" | cut -s -f3 | sed "/^$/d")
  fi
	inv_dif=$(echo "$inv_dif" | cut -f1 | sed "/^$/d")
	inv_dif=$(echo "$inv_dif" | sed "s/|.*[[:digit:]]|$/|/g")
	deleted[$it1]=$(comm -23 <(echo "$inv_dif" | sort) <(echo "${mod[$it1]}" | sed "s/|.*[[:digit:]]|$/|/g" | sort) | sed "/^$/d")
	mod[$it1]=$(echo "${mod[$it1]}" | sed -e "s/$/Mod/g")
	deleted[$it1]=$(echo "${deleted[$it1]}" | sed -e "s/$/Del/g")
	list[$it1]=$(echo "${same[$it1]}"; echo "${mod[$it1]}"; echo "${deleted[$it1]}")
	list[$it1]=$(echo "${list[$it1]}" | sed "/^$/d")
	list[$it1]=$(echo "${list[$it1]}" | grep -v "^Del$" | cat)
	list[$it1]=$(echo "${list[$it1]}" | grep -v "^Mod$" | cat)
done
diferences=$(comm <(echo "${list[1]}" | sort) <(echo "${list[2]}" | sort))
inventory_list=$(echo "$diferences" | cut -s -f3 | sed '/^$/d')
inventory_list=$(echo "$inventory_list" | grep -v "^Del$" | cat)
inventory_list=$(echo "$inventory_list" | sed "s,Mod$,,g")
list[1]=$(echo "$diferences" | cut -f1 | grep -v "|$" | cat | sed "/^$/d")
list[2]=$(echo "$diferences" | cut -s -f2 | grep -v "|$" | cat | sed "/^$/d")
epoch_adjustment=0
touch_value=$(eval "$adb_shell""'touch --help 2>&1'" </dev/tty)
case "$touch_value" in
	*'[-t TIME]'*)
		touch_value="date"
	;;
	*'[-t time_t]'*)
		touch_value="epoch"
	;;
	*)
		do_not_use_su=true
	;;
esac
if [ -z "$inventory_file" ];then
	present_in_both=$(comm -12 <(echo "${list[1]}" | cut -f1,2 -d "|" | sort) <(echo "${list[2]}" | cut -f1,2 -d "|" | sort) | sed '/^$/d')
	present_in_both=$(echo "$present_in_both" | cut -f1 -d "|")
	if [ -n "$present_in_both" ];then
		message=$(echo "I found a file that is present both in the android device and local device witch has the same size but different modification date. It might be the exact same file, a copy made by you perhaps? If this is the case, click YES to change its modification date so that it matches and treated as such, other wise, click NO and you will be prompt to choose which version to keep instead.

The above-mentioned file is the following:")
		present_in_both=$(echo "$present_in_both" | sed '/^$/d' | sort)
		if [ $(echo "$present_in_both" | wc -l) -gt "1" ];then
			message=$(echo "I found some files that are present both in the android device and local device witch have the same size but different modification date. They might be the exact same files, copies made by you perhaps? If this is the case, click YES to change their modification date so that they match and treated as such, other wise, click NO and you will be prompt to choose which version to keep instead.

The above-mentioned files are the following:")
		fi
		ask_question "It appears that this is the first time you are running 'adb-sync-two-way-plus'.

$message:

$present_in_both"
		if [ "$answered" == "TRUE" ];then
			while read -r; do
				file_name="$REPLY"
				for it2 in 1 2;do
					side[$it2]=$(echo "${list[$it2]}" | grep -F "$file_name|")
					epoch[$it2]=$(echo "${side[$it2]}" | cut -f3 -d "|")
					list[$it2]=$(echo "${list[$it2]}" | grep -F -v "$file_name|" | cat)
				done
				if [ "${epoch[2]}" -lt "${epoch[1]}" ];then
					update_android_date
				else
					date_var[1]=$(date "+%Y%m%d%H%M.%S" -d @$((epoch[1])))
					touch -m -t ${date_var[1]} "$file_name"
					inventory_list+=$'\n'"${side[1]}"
				fi
			done <<< "$present_in_both"
		fi
	fi
fi
present_in_both=$(comm -12 <(echo "${list[1]}" | grep -v "|Directory" | cat | cut -f1 -d "|" | sort) <(echo "${list[2]}" | grep -v "|Directory" | cat | cut -f1 -d "|" | sort))
if [ "$present_in_both" != "" ];then
	instances=$(echo "$present_in_both" | wc -l)
	title="Choose and action to be taken"
	options[1]='Keep both files, renaming the oldest one by adding its modification date/time to its name.
Keep only the one with the newest modifications.
Keep the old one instead.'
	options[2]="Delete the file.
Don't deleted the file, and keep the the modified one."
	additional[1]='Choose to keep both for the rest ($instances) number of occurrences.
Choose to keep the newest for the rest ($instances) number of occurrences.
Choose to keep the old one instead for the rest ($instances) number of occurrences.
Choose to keep the local version for the rest ($instances) number of occurrences.
Choose to keep the android version for the rest ($instances) number of occurrences.'
	additional[2]='Choose to delete the file over keeping the modified version for the rest ($instances) number of occurrences.
Choose not to the delete a file if it was modified for the rest ($instances) number of occurrences.
Choose the local operation, whether it is deletion or modification for the rest ($instances) number of occurrences.
Choose the android operation, whether it is deletion or modification for the rest ($instances) number of occurrences.'
	column_name="Action to be taken"
	while read -r; do
		let "instances--"
		file_name="$REPLY"
		for it3 in 1 2;do
            place="Android"
            [ $it3 -eq 2 ] && place="Local"
            side[$it3]=$(echo "${list[$it3]}" | grep -F "$file_name|")
            status[$it3]=$(echo "${side[$it3]}" | sed "s/.*|//g")
            if [ "${status[$it3]}" == "Mod" ];then
                size[$it3]=$(echo "${side[$it3]}" | cut -f2 -d "|")" bytes"
                epoch[$it3]=$(echo "${side[$it3]}" | cut -f3 -d "|")
                date[$it3]=$(date "+%Y-%m-%d %H:%M:%S" -d @$((epoch[$it3])))
                status_desc[$it3]="<b>$place version was modified on ${date[$it3]} (${size[$it3]})</b>"
            else
                status_desc[$it3]="<b>$place version was deleted.</b>"
            fi
		done
		if ([ "${status[1]}" == "${status[2]}" ] && [ "$mod_vs_mod" == "" ]) || ([ "${status[1]}" != "${status[2]}" ] && [ "$mod_vs_del" == "" ]);then
			op_num=1
			[ "${status[1]}" != "${status[2]}" ] && op_num=2
			final_options="${options[$op_num]}"
			[ "$instances" -gt "0" ] && final_options+=$'\n'$(eval "echo \"${additional[$op_num]}\"")
			ask_list "$column_name" "$final_options" "$title" "The file '\''<b>$file_name</b>'\'' presents modifications from both the local computer and the android device since last time they were sync. What should I do?

${status_desc[1]}
${status_desc[2]}

Note: Option -m and -d can be used so that this question isn'\''t asked next time."
			answer=$(echo "$answer" | cut -f1 -d "|")
			if [ "${status[1]}" == "${status[2]}" ];then
				mod_vs_mod="$answer"
			else
				mod_vs_del="$answer"
			fi
		fi
		if [ "${status[1]}" == "${status[2]}" ];then
			case "$mod_vs_mod" in
				[14])
					if [ "${epoch[1]}" -lt "${epoch[2]}" ];then
						list[1]=$(echo "${list[1]}" | grep -F -v "$file_name|" | cat)
						rename="$file_name""_${date_var[1]}"
						oldest_file="Android|"$(echo ${side[1]} | cut -f2,3 -d "|")
					else
						list[2]=$(echo "${list[2]}" | grep -F -v "$file_name|" | cat)
						rename="$file_name""_${date_var[2]}"
						oldest_file="Local|"$(echo "${side[2]}" | cut -f2,3 -d "|")
					fi
					rename_list+="$file_name|$rename|$oldest_file"$'\n'
				;;
				[25])
					if [ "${epoch[1]}" -lt "${epoch[2]}" ];then
						list[1]=$(echo "${list[1]}" | grep -F -v "$file_name|" | cat)
					else
						list[2]=$(echo "${list[2]}" | grep -F -v "$file_name|" | cat)
					fi
				;;
				[36])
					if [ "${epoch[1]}" -gt "${epoch[2]}" ];then
						list[1]=$(echo "${list[1]}" | grep -F -v "$file_name|"| cat)
					else
						list[2]=$(echo "${list[2]}" | grep -F -v "$file_name|" | cat)
					fi
				;;
				7)
					list[1]=$(echo "${list[1]}" | grep -F -v "$file_name|" | cat)
				;;
				8)
					list[2]=$(echo "${list[2]}" | grep -F -v "$file_name|" | cat)
				;;
			esac
			if [ "$mod_vs_mod" -le "3" ];then
				mod_vs_mod=""
			fi
		else
			case "$mod_vs_del" in
				[13])
					if [ "${status[1]}" == "Del" ];then
						list[2]=$(echo "${list[2]}" | grep -F -v "$file_name|" | cat)
					else
						list[1]=$(echo "${list[1]}" | grep -F -v "$file_name|" | cat)
					fi
				;;
				[24])
					if [ "${status[1]}" == "Del" ];then
						list[1]=$(echo "${list[1]}" | grep -F -v "$file_name|" | cat)
					else
						list[2]=$(echo "${list[2]}" | grep -F -v "$file_name|" | cat)
					fi
				;;
				5)
					list[1]=$(echo "${list[1]}" | grep -F -v "$file_name|" | cat)
				;;
				6)
					list[2]=$(echo "${list[2]}" | grep -F -v "$file_name|" | cat)
				;;
			esac
			if [ "$mod_vs_del" -le "2" ];then
				mod_vs_del=""
			fi
		fi
	done <<< "$present_in_both"
fi
if [ -n "$rename_list" ];then
	while read -r; do
		rename=$(echo $REPLY | cut -f2 -d "|" | sed "s,:,hr," | sed "s,:,min,")"sec"
		rename_escaped=$(echo "$rename" | sed "s,','\"'\"'\"'\"'\"'\"'\"'\"',g")
		count=1
		while [ -f "$rename" ] || [ -d "$rename" ] || [[ $(eval "$adb_shell""'([ -f '\"'\"'$rename_escaped'\"'\"' ] || [ -d '\"'\"'$rename_escaped'\"'\"' ]) && echo TRUE'" </dev/tty) ]];do
			count=$((count+1))
			rename=$(echo $rename | sed "s,(.*)$,,")
			rename="$rename($count)"
			rename_escaped=$(echo "$rename" | sed "s,','\"'\"'\"'\"'\"'\"'\"'\"',g")
		done
		file_name=$(echo $REPLY | cut -f1 -d "|")
		file_name_escaped=$(echo "$file_name" | sed "s,','\"'\"'\"'\"'\"'\"'\"'\"',g")
		from=$(echo $REPLY | cut -f3 -d "|")
		if [ "$from" == "Android" ];then
			eval "$adb_shell""' mv '\"'\"'$file_name_escaped'\"'\"' '\"'\"'$rename_escaped'\"'\"" </dev/tty
			list[1]+=$'\n'"$rename|"$(echo $REPLY | cut -f4,5 -d "|")"|Mod"
		else
			if [ "$from" == "Local" ];then
				mv "$file_name" "$rename"
				list[2]+=$'\n'"$rename|"$(echo $REPLY | cut -f4,5 -d "|")"|Mod"
			fi
		fi
	done <<< "$rename_list"
fi
for it4 in 1 2;do
    new_directories[$it4]=$(echo "${list[$it4]}" | grep "Directory|Mod$" | cut -f1 -d "|" | cat | sort)
    new_mod_files[$it4]=$(echo "${list[$it4]}" | grep -v "|Directory|" | grep "Mod$" | cat | sort)
    deleted_files[$it4]=$(echo "${list[$it4]}" | grep -v "|Directory|" | grep "Del$" | cat | sort)
    deleted_directories[$it4]=$(echo "${list[$it4]}" | grep "Directory|Del$" | cat | sort)
done
for i in "y=1; x=2" "y=2; x=1";do
	eval "$i"
    if [ -n "${deleted_files[$y]}" ] && [ -n "${new_mod_files[$y]}" ];then
      deleted_files[$y]=$(echo "${deleted_files[$y]}" | cut -f1 -d "|")
      files_to_delete=""
      while read -r; do
          files_to_delete+=$'\n'$(echo "${list_untouch[$x]}" | grep "$REPLY" | cat)
      done <<< "${deleted_files[$y]}"
      files_to_delete=$(echo "$files_to_delete" | tail -n +2)
      for i in 1 2 3;do
          if [ -z "${deleted_files[$y]}" ] || [ -z "${new_mod_files[$y]}" ];then
              break
          fi
          files_to_delete_list=$(echo "$files_to_delete" | sed "s,.*/,,g")
          new_mod_files_list[$y]=$(echo "${new_mod_files[$y]}" | sed "s,Mod$,,g" | sed "s,.*/,,g")
	        case $i in
		        2)
                files_to_delete_list=$(echo "$files_to_delete_list" | grep -E "\.[A-Za-z0-9]{1,4}\|" | sed "s,.*\.,,g")
                new_mod_files_list[$y]=$(echo "${new_mod_files_list[$y]}" | grep -E "\.[A-Za-z0-9]{1,4}\|" | sed "s,.*\.,,g")
		        ;;
		        3)
                files_to_delete_list=$(echo "$files_to_delete_list" | grep -v -E "\.[A-Za-z0-9]{1,4}\|" | sed "s,^[^|]*|,,g")
                new_mod_files_list[$y]=$(echo "${new_mod_files_list[$y]}" | grep -v -E "\.[A-Za-z0-9]{1,4}\|" | sed "s,^[^|]*|,,g")
		        ;;
           esac
          founds=$(comm -12 <(echo "$files_to_delete_list" | sed "/^$/d" | sort) <(echo "${new_mod_files_list[$y]}" | sed "/^$/d" | sort))
          if [ -n "$founds" ]; then
             	while read -r; do
                  original=$(echo "$files_to_delete" | grep -m1 "$REPLY")
                  original_location=$(echo "$original" | cut -f1 -d "|")
                  original_epoch=$(echo "$original" | cut -f3 -d "|")
                  files_to_delete=$(echo "$files_to_delete" | grep -v "$original_location" | cat)
                  deleted_files[$y]=$(echo "${deleted_files[$y]}" | grep -v "$original_location" | cat)
                  new=$(echo "${new_mod_files[$y]}" | grep -m1 "$REPLY")
                  new_location=$(echo "$new" | cut -f1 -d "|")
                  new_mod_files[$y]=$(echo "${new_mod_files[$y]}" | grep -v "$new_location"  | cat)
                  if [ "$y" -eq 2 ];then
		                  original_location_escaped=$(echo "$original_location" | sed "s,','\"'\"'\"'\"'\"'\"'\"'\"',g")
		                  new_location_escaped=$(echo "$new_location" | sed "s,','\"'\"'\"'\"'\"'\"'\"'\"',g")
                			current_epoch=$(eval "$adb_shell""' mv '\"'\"'$original_location_escaped'\"'\"' '\"'\"'$new_location_escaped'\"'\"'; stat '\"'\"'$new_location_escaped'\"'\"' -c %Y'" </dev/tty | tr -d "\r")
		                  if [ "$current_epoch" != "$original_epoch" ];then
                        file_name="$new_location"
                        epoch[1]="$current_epoch"
                        epoch[2]="$original_epoch"
                  			side[1]=$(echo "$new" | cut -f1,2 -d "|")"|$current_epoch"
                        side[2]="$new"
			                  update_android_date
		                  fi
                  else
				              mv "$original_location" "$new_location"
                  fi
              done <<< "$founds"
          fi
      done
    fi
done
if [ -n "${deleted_files[1]}" ];then
  something_done=true
	while read -r; do
		file_name=$(echo "$REPLY" | cut -f1 -d "|")
    if [ "$dont_use_trash" == "TRUE" ];then
        rm "$file_name"
    else
        gvfs-trash "$file_name"
    fi
	done <<< "${deleted_files[1]}"
fi
if [ -n "${deleted_directories[1]}" ];then
  something_done=true
	while read -r; do
		file_name=$(echo "$REPLY" | cut -f1 -d "|")
    if [ "$dont_use_trash" == "TRUE" ];then
        rm -r "$file_name"
    else
        gvfs-trash "$file_name"
    fi
	done <<< "${deleted_directories[1]}"
fi
if [ -n "${deleted_files[2]}" ];then
  something_done=true
	while read -r; do
		file_name=$(echo "$REPLY" | cut -f1 -d "|")
		file_name_escaped=$(echo "$file_name" | sed "s,','\"'\"'\"'\"'\"'\"'\"'\"',g")
		eval "$adb_shell""'rm '\"'\"'$file_name_escaped'\"'\"" </dev/tty    
	done <<< "${deleted_files[2]}"
fi
if [ -n "${deleted_directories[2]}" ];then
  something_done=true
	while read -r; do
		file_name=$(echo "$REPLY" | cut -f1 -d "|")
		file_name_escaped=$(echo "$file_name" | sed "s,','\"'\"'\"'\"'\"'\"'\"'\"',g")
		eval "$adb_shell""'rm -r '\"'\"'$file_name_escaped'\"'\"" </dev/tty    
	done <<< "${deleted_directories[2]}"
fi
if [ -n "${new_directories[1]}" ];then
    something_done=true
	while read -r; do
        mkdir "$REPLY"
	done <<< "${new_directories[1]}"
fi
if [ -n "${new_directories[2]}" ];then
  something_done=true
	while read -r; do
		new_directory=$(echo "$REPLY" | cut -f1 -d "|")
		new_directory_escaped=$(echo "$new_directory" | sed "s,','\"'\"'\"'\"'\"'\"'\"'\"',g")
		eval "$adb_shell""' mkdir '\"'\"'$new_directory_escaped'\"'\"" </dev/tty
	done <<< "${new_directories[2]}"
fi
inventory_list+=$'\n'"${new_directories[1]}"
inventory_list+=$'\n'"${new_directories[2]}"
push_a_works=true
what_to_do="Pull"
for i in 1 2;do
    [ $i == 2 ] && what_to_do="Push"
    if [ -n "${new_mod_files[$i]}" ];then
        something_done=true
        number_of_files_to=$(echo "${new_mod_files[$i]}" | wc -l)
        percentage=0
        number_of_file=1
        bytes_to=$(echo "${new_mod_files[$i]}" | cut -f2 -d "|" | paste -s -d+ - | bc)
        bytes_done=0
        bytes_ended_now=0
	    while read -r; do
            bytes_ended=0
	        file_name=$(echo "$REPLY" | cut -f1 -d "|")
            file_name2=$(echo "$file_name" | sed "s,^./,,")
            percentage=$(($bytes_done * 100 / $bytes_to))
	        file_size=$(echo "$REPLY" | cut -f2 -d "|")
            if [ -z "$no_progress_bars" ] && [ -n "$use_zenity" ];then
                overall="${what_to_do}ing file $number_of_file of $number_of_files_to\\n$bytes_done/$bytes_to ($percentage%) bytes finished."
                echo "#File: $file_name\\nTransferring:\\n\\n$overall"
                echo "$percentage"
                if [ $i == 1 ];then
                    "$adb" -s "${serial[1]}" pull -p "${path[1]}/$file_name2" "$file_name" 2>&1
                else
                    "$adb" -s "${serial[1]}" push -p -a "$file_name" "${path[1]}/$file_name2" 2>&1
                fi | unbuffer -p cat |
                while read OUT;do
                    OUT=$(echo "$OUT" | tr -d "\r")
                    percentage_of_file=$(echo "$OUT" | grep -o '[0-9]*%' | head -1 | sed "s,%,,")
                    if [[ $percentage_of_file =~ ^-?[0-9]+$ ]];then
                        bytes_ended=$(($percentage_of_file * $file_size / 100))
                        bytes_ended_now=$(($bytes_done+$bytes_ended))
                    fi
                    percentage=$(($bytes_ended_now * 100 / $bytes_to))
                    overall="${what_to_do}ing file $number_of_file of $number_of_files_to\\n$bytes_ended_now/$bytes_to ($percentage%) bytes finished."
                    echo "#File: $file_name\\n$OUT\\n\\n$overall"
                    echo "$percentage"
                done
                result_start=$("$adb" start-server)
                if [[ "$result_start" != "" ]];then
		            file_name_escaped=$(echo "$file_name" | sed "s,','\"'\"'\"'\"'\"'\"'\"'\"',g")
		            eval "$adb_shell""'rm '\"'\"'$file_name_escaped'\"'\"" </dev/tty
                    exit
                fi
                state[1]=$(eval "$adb_escaped get-state" 2>&1)
                if [ $? -ne 0 ];then
                    error_this "The android device was disconnected. This can cause storage corruption. I recommend you to connect the device again and use “adb start-server” before anything, other wise, try rebooting your device in case you experience any problem." "0" "1"
                    canceled_before_finished
                    exit
                fi
            else
                echo "$bytes_done/$bytes_to ($percentage%) bytes finished."
                overall="${what_to_do}ing file $number_of_file of $number_of_files_to"
                echo "File: $file_name"$'\n'"$overall"
                if [ $i == 1 ];then
            	    "$adb" -s "${serial[1]}" pull -p "${path[1]}/$file_name" "./$file_name" </dev/tty
                else
                    "$adb" -s "${serial[1]}" push -p -a "$file_name" "${path[1]}/$file_name2" </dev/tty
                fi
            fi
            number_of_file=$((number_of_file + 1))
            bytes_done=$(($bytes_done+$file_size))
            epoch[1]=$(echo "$REPLY" | cut -f3 -d "|")
            if [ $i == 1 ];then
	            date_to_use=$(date "+%Y%m%d%H%M.%S" -d @$((epoch[1])))
	            touch -m -t $date_to_use "./$file_name"
            else
                if [ "$push_a_works" == "true" ];then
                    file_name_escaped=$(echo "$file_name" | sed "s,','\"'\"'\"'\"'\"'\"'\"'\"',g")
                    current_epoch=$(eval "$adb_shell""' stat '\"'\"'$file_name_escaped'\"'\"' -c %Y'" </dev/tty | tr -d "\r")
                    epoch[2]=${epoch[1]}
                    side[2]="$REPLY"
                    if [ "$current_epoch" -ne  "${epoch[2]}" ];then
                        push_a_works=false
                    fi
                fi
                if [ "$push_a_works" == "false" ];then
                    update_android_date
                else
                   	inventory_list+=$'\n'"${side[2]}"
                fi
            fi
	    done <<< "${new_mod_files[$i]}" |
        if [ -z "$no_progress_bars" ] && [ -n "$use_zenity" ];then
            zenity --progress --auto-close --title="${what_to_do}ing files" --text="Italicizing ${what_to_do}ing Process..." --percentage="0" --width=600
            if [ "$?" -eq 1 ];then
                "$adb" kill-server
                canceled_before_finished
            fi
        else
            cat
        fi
	    inventory_list+=$'\n'"${new_mod_files[$i]}"
    fi
done
inventory_list=$(echo "$inventory_list" | sed "s,Mod$,,g" | sed "/^$/d")
if [ "$inventory_list" != "" ];then
	inventory_list="${serial[1]}|${path[1]}"$'\n'"$inventory_list"
fi
echo "$inventory_list" > ./.sync_inventory.log
if [[ $something_done == true ]];then
  info_this "Sync finished succesfuly." "All done."
else
  info_this "Nothing new to be sync." "Sync ended correctly."
fi
