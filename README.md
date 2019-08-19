# adb-sync-two-way-plus
File and directorie(s) two way synchronization using adb (android debug bridge).

USAGE: adb-sync-two-way-plus.sh Android_absolute_path Local_absolute_path [OPTIONAL Arguments]
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
                      dialog boxes from appearing even if option “-g” is given.

    -w                Normally, this script will show warns whenever it finds
                      an abnormality. For instance, there might be a local file
                      with a name that has an unsupported character for a file
                      on android, which will prevent it from being sync. Every
                      time a warn is given, the user will be asked if it wants
                      to continue anyway, for instance, without syncing those
                      files in the above mentioned example. By using this
                      parameter, the   user won’t be asked, and all warnings
                      will be answered with a “yes”, and the script will
                      continue without any stop.
