#!/bin/zsh

# UnActivationLock
# An Activation Lock / iCloud Logout Prompt

# This script checks to see if a machine is Activation locked by a user, and if so,
# it will try to determine if the currently logged in user is the one associated with 
# the activation lock, and prompt the user to turn off Find My Mac.

########################################################################################
# Created by Brian Van Peski - macOS Adventures
########################################################################################
# Current version: 1.5 (draft) | See CHANGELOG for full version history.
# Updated: 01/30/2023

# Set logging - Send logs to stdout as well as Unified Log
# Use 'log show --process "logger"'to view logs activity.
function LOGGING {
    echo "${1}"
    /usr/bin/logger "UnActivationLock: ${1}"
}

##############################################################
# USER INPUT 
##############################################################
# Messaging
dialogTitle="Turn off Find My Mac"
dialogMessage="This company device is currently locked to your iCloud account. Please turn off Find My Mac under iCloud > Find My Mac."
appIcon="/System/Library/PrivateFrameworks/AOSUI.framework/Versions/A/Resources/findmy.icns" #Path to app icon for messaging (optional)

DisallowFindMy=false #Change to true if you want to *always* prompt the user when Find My Mac is enabled, regardless of the user-based activation lock status.

wait_time=40 #How many seconds to wait until re-prompting the user.
timeout=90 #How long to try prompting the user until giving up.

##############################################################
# VARIABLES & FUNCTIONS
##############################################################
currentUser=$(ls -la /dev/console | awk '{print $3}')
activationLock=$(/usr/sbin/system_profiler SPHardwareDataType | awk '/Activation Lock Status/{print $NF}')
plist="/Users/$currentUser/Library/Preferences/MobileMeAccounts.plist"
DEPStatus=$(profiles status -type enrollment | grep "Enrolled via DEP" | awk '{print $4}')
FindMyEnabled=$(/usr/libexec/PlistBuddy -c print "$plist" | grep -A1 "FIND_MY_MAC" | awk 'FNR == 2 {print $3}' ) #Checks dictionary to make sure proper user is targeted [if FindMy = then, continue]
KandjiAgent="/Library/Kandji/Kandji Agent.app"

UserLookup (){
## Fetch all local user accounts, return account with iCloud FindMyStatus enabled.
USER_LIST=($(/usr/bin/dscl /Local/Default -list /Users UniqueID | /usr/bin/awk '$2 >= 500 {print $1}'|tr '\n' ' ' ))
LOGGING "--- Checking Activation Lock status for the following users: $USER_LIST..."
for user in "${USER_LIST[@]}"; do
    plistLookup="/Users/${user}/Library/Preferences/MobileMeAccounts.plist"
    #LOGGING "--- Checking Activation Lock status for $user..."
    if [[ -f $plistLookup ]]; then
      FindMyEnabled=$(/usr/libexec/PlistBuddy -c print "/Users/${user}/Library/Preferences/MobileMeAccounts.plist" | grep -A1 "FIND_MY_MAC" | awk 'FNR == 2 {print $3}' )
      #LOGGING "Find My Status for $user is: $FindMyEnabled"
      if [[ $FindMyEnabled == "true" ]]; then
      LOGGING "Find My is enabled for user $user"
      FindMyUser="$user"
      FindMyEmail=$(/usr/libexec/PlistBuddy -c 'print Accounts:0:AccountID' "/Users/$user/Library/Preferences/MobileMeAccounts.plist")
      fi
    else
      #LOGGING "No iCloud login found for $user"
    fi
done
}

UserDialog (){
  # Check if $appIcon file exists on system, if not use standard dialog. If
  # Kandji agent is not installed, default to applescript dialog.
  if [[ -f $appIcon && ! -d $KandjiAgent ]]; then
    /usr/bin/osascript -e 'display dialog "'$dialogMessage'" with title "'$dialogTitle'" with icon POSIX file "'$appIcon'" buttons {"Okay"} default button 1 giving up after 15'
  elif [[ -f $appIcon && -d $KandjiAgent ]]; then
    /usr/local/bin/kandji display-alert --title ''$dialogTitle'' --message ''$dialogMessage'' --icon $appIcon
  elif [[ ! -f $appIcon && -d $KandjiAgent ]]; then
    /usr/local/bin/kandji display-alert --title ''$dialogTitle'' --message ''$dialogMessage''
  else
    /usr/bin/osascript -e 'display dialog "'$dialogMessage'" with title "'$dialogTitle'" buttons {"Okay"} default button 1 giving up after 15'
  fi
}

##############################################################
#  THE NEEDFUL
##############################################################
LOGGING "Activation Lock Status: $activationLock | ADE-Enrolled: $DEPStatus"
#Check if Kandji Liftoff is running
if pgrep "Liftoff" >/dev/null; then
    LOGGING "--- Liftoff is running. Exiting to wait for apps to finish installing..."
    exit 0
# Check if Activation Lock is enabled.
elif [[ $activationLock == "Enabled" ]]; then
  LOGGING "--- User-Based Activation Lock is: Enabled. Checking local users..."
  UserLookup
  #Determine the FindMy enabled user and see if it matches the currently logged in user.
  SECONDS=0
  if [[ -f "$plist" && "$FindMyUser" == "$currentUser" ]]; then
    until [[ $activationLock == "Disabled" ]]
      do
        if (( $SECONDS > $timeout )); then
          LOGGING "Prompts have been ignored for more than $timeout seconds. Giving up..."
          exit 1
        fi
        LOGGING "--- Found logged in iCloud account '$FindMyUser'... Presenting pane to user and requesting user to log out..."
        open "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane?iCloud"
        osascript -e 'tell application "System Settings"' -e 'activate' -e 'end tell'
        UserDialog
        sleep $wait_time
        export activationLock=$(/usr/sbin/system_profiler SPHardwareDataType | awk '/Activation Lock Status/{print $NF}')
      done
    LOGGING "Activation Lock Status: $activationLock"
    exit 0
    elif [[ $activationLock == "Enabled" && -z $FindMyUser ]]; then
      LOGGING "Activation lock status is $activationLock, and there are no users with a FindMy token associated. Something is wonky..."
      #I don't think this can happen, but leaving it here just in case.
      exit 1
    else
      LOGGING "--- The currently logged in user: '$currentUser' is not the user associated with the Activation Lock.
      --- Activation Lock status is: $activationLock, and is locked by user '$FindMyUser' with account '$FindMyEmail'.
      --- Script will continue to run until the appropriate user logs in and is prompted to turn off Find My.
      Exiting..."
      exit 1
  fi
else
  UserLookup
  if [[ $DisallowFindMy == true && "$FindMyUser" == "$currentUser" ]]; then
    until [[ $FindMyEnabled == false ]]
      do
        if (( $SECONDS > $timeout )); then
        LOGGING "Prompts have been ignored for more than $timeout seconds. Giving up..."
        exit 1
        fi
        LOGGING "--- Found logged in iCloud account for user '$FindMyUser' with account '$FindMyEmail'... Presenting pane to user and requesting user to log out of Find My Mac."
        open "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane?iCloud"
        osascript -e 'tell application "System Settings"' -e 'activate' -e 'end tell'
        UserDialog
        sleep $wait_time
        #export FindMyStatus
        export FindMyEnabled=$(/usr/libexec/PlistBuddy -c print "$plist" | grep -A1 "FIND_MY_MAC" | awk 'FNR == 2 {print $3}')
      done
  fi
  LOGGING "--- User-based Activation Lock not enabled.
  --- Find My Mac status for $currentUser is: $FindMyEnabled.
  Exiting..."
  exit 0
fi
