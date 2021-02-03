#!/bin/bash

:<<DOC
autopkg_setup_for_jamfuploader.sh
by Graham Pugh

This script automates the installation of the latest version
of AutoPkg and prerequisites for using JamfUploader processors

Acknowledgements:
Excerpts from https://github.com/grahampugh/run-munki-run
which in turn borrows from https://github.com/tbridge/munki-in-a-box

--------------------------------------------------------------------------------------
This script will ask for a URL and API credentials for your Jamf server
You can also supply a repo-list which will all be added to the AutoPkg prefs
--------------------------------------------------------------------------------------
DOC

HELP=<<HELP
Usage:
./autopkg_setup_for_jamfuploader.sh +

-h | --help         display this text
--force        force the re-installation of the latest AutoPkg 
--url               the JSS_URL
--api-user          the API_USERNAME
--api-pass          the API_PASSWORD
--smb-url           the SMB_URL
--smb-user          the SMB_USERNAME
--smb-pass          the SMB_PASSWORD
--slack-webhook     a Slack Webhook
--slack-user        a username to display in Slack notifications
--prefs             path to the preferences plist
HELP


rootCheck() {
    # Check that the script is NOT running as root
    if [[ $EUID -eq 0 ]]; then
        echo "   [setup] This script is NOT MEANT to run as root."
        echo "   [setup] This script is meant to be run as an admin user."
        echo "   [setup] Please run without sudo."
        echo
        exit 4 # Running as root.
    fi
}

installCommandLineTools() {
    # Installing the Xcode command line tools on 10.10+
    # This section written by Rich Trouton.
    echo "   [setup] Installing the command line tools..."
    echo
    cmd_line_tools_temp_file="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"

    # Installing the latest Xcode command line tools on 10.9.x or above
    osx_vers=$(sw_vers -buildVersion)
    if [[ "${osx_vers:0:2}" -ge 13 ]] ; then

        # Create the placeholder file which is checked by the softwareupdate tool
        # before allowing the installation of the Xcode command line tools.
        touch "$cmd_line_tools_temp_file"

        # Find the last listed update in the Software Update feed with "Command Line Tools" in the name
        cmd_line_tools=$(softwareupdate -l | grep "Label: Command Line Tools" | sed 's|^\* Label: ||')

        #Install the command line tools
        sudo softwareupdate -i "$cmd_line_tools"

        # Remove the temp file
        if [[ -f "$cmd_line_tools_temp_file" ]]; then
            rm "$cmd_line_tools_temp_file"
        fi
    else
        echo "   [setup] ERROR: this script is only for use on OS X/macOS >= 10.9"
    fi
}

installAutoPkg() {
    # Get AutoPkg
    # thanks to Nate Felton
    # Inputs: 1. $USERHOME
    AUTOPKG_LATEST=$(curl https://api.github.com/repos/autopkg/autopkg/releases/latest | python -c 'import json,sys;obj=json.load(sys.stdin);print obj["assets"][0]["browser_download_url"]')
    /usr/bin/curl -L "${AUTOPKG_LATEST}" -o "$1/autopkg-latest.pkg"

    sudo installer -pkg "$1/autopkg-latest.pkg" -target /

    autopkg_version=$(${AUTOPKG} version)

    ${LOGGER} "AutoPkg $autopkg_version Installed"
    echo
    echo "   [setup] AutoPkg $autopkg_version Installed"
    echo

    # Clean Up When Done
    rm "$1/autopkg-latest.pkg"
}

configureSlack() {
    # get Slack user
    if [[ "${SLACK_USER}" ]]; then
        ${DEFAULTS} write "$AUTOPKG_PREFS" SLACK_USER "${SLACK_USER}"
        echo "   [setup] Slack user ${SLACK_USER} written to $AUTOPKG_PREFS"
    fi

    # get Slack webhook
    if [[ "${SLACK_WEBHOOK}" ]]; then
        ${DEFAULTS} write "$AUTOPKG_PREFS" SLACK_WEBHOOK "${SLACK_WEBHOOK}"
        echo "   [setup] Slack webhook written to $AUTOPKG_PREFS"
    fi
    echo
}

## Main section

# Commands
GIT="/usr/bin/git"
DEFAULTS="/usr/bin/defaults"
AUTOPKG="/usr/local/bin/autopkg"

# logger
LOGGER="/usr/bin/logger -t AutoPkg_Setup"

# get arguments
while test $# -gt 0
do
    case "$1" in
        --force) force_autopkg_update="yes"
        ;;
        --smb) smb_repo="yes"
        ;;
        --prefs)
            shift
            AUTOPKG_PREFS="$1"
            [[ $AUTOPKG_PREFS == "/"* ]] || AUTOPKG_PREFS="$(pwd)/${AUTOPKG_PREFS}"
            [[ $AUTOPKG_PREFS != *".plist" ]] && AUTOPKG_PREFS="${AUTOPKG_PREFS}.plist"
            echo "   [setup] AUTOPKG_PREFS : $AUTOPKG_PREFS"
        ;;
        --recipe-list)
            shift
            AUTOPKG_RECIPE_LIST="$1"
        ;;
        --repo-list)
            shift
            AUTOPKG_REPO_LIST="$1"
        ;;
        --smb-url)
            shift
            SMB_URL="$1"
        ;;
        --smb-user)
            shift
            SMB_USERNAME="$1"
        ;;
        --smb-pass)
            shift
            SMB_PASSWORD="$1"
        ;;
        --url)
            shift
            JSS_URL="$1"
        ;;
        --api-user)
            shift
            API_USERNAME="$1"
        ;;
        --api-pass)
            shift
            API_PASSWORD="$1"
        ;;
        --slack-webhook)
            shift
            SLACK_WEBHOOK="$1"
        ;;
        --slack-user)
            shift
            SLACK_USER="$1"
        ;;
        *)
            echo "$HELP"
            exit 0
        ;;
    esac
    shift
done

# Check for Command line tools.

if ! xcode-select -p >/dev/null 2>&1 ; then
    installCommandLineTools
fi

# check CLI tools are functional

if ! $GIT --version >/dev/null 2>&1 ; then
    installCommandLineTools
fi

# Get AutoPkg if not already installed
if [[ ! -f "${AUTOPKG}" || $force_autopkg_update == "yes" ]]; then
    installAutoPkg "${HOME}"
    ${LOGGER} "AutoPkg installed and secured"
    echo
    echo "   [setup] AutoPkg installed and secured"
fi

# read the supplied prefs file or else use the default
if [[ $AUTOPKG_PREFS && -f "$HOME/Library/Preferences/com.github.autopkg.plist" ]]; then
    ${LOGGER} "$AUTOPKG_PREFS provided but com.github.autopkg domain already exists."
    echo
    echo "   [setup] $AUTOPKG_PREFS provided but com.github.autopkg domain already exists."
    echo "   [setup] This could result in unexpected behaviour. Consider \"defaults delete com.github.autopkg\"."
elif [[ ! $AUTOPKG_PREFS ]]; then
    AUTOPKG_PREFS="$HOME/Library/Preferences/com.github.autopkg.plist"
    ${LOGGER} "AutoPkg prefs path not supplied - defaulting to $AUTOPKG_PREFS"
    echo
    echo "   [setup] AutoPkg prefs path not supplied - defaulting to $AUTOPKG_PREFS"
fi

# check that the prefs exist and are valid
if /usr/bin/plutil -lint "$AUTOPKG_PREFS" ; then 
    ${LOGGER} "$AUTOPKG_PREFS is a valid plist"
    echo
    echo "   [setup] $AUTOPKG_PREFS is a valid plist"
else
    ${LOGGER} "$AUTOPKG_PREFS is not a valid plist! Creating a new one."
    echo
    echo "   [setup] $AUTOPKG_PREFS is not a valid plist! Creating a new one:"
    # create a new one with basic entries and take it from there
    rm -f "$AUTOPKG_PREFS" ||:

    # write git path (this creates the AutoPkg prefs file and populates the GIT_PATH key)
    ${DEFAULTS} write "${AUTOPKG_PREFS}" GIT_PATH "$GIT"
    ${LOGGER} "Wrote GIT_PATH ($GIT) to $AUTOPKG_PREFS"
    echo
    echo "   [setup] Wrote GIT_PATH ($GIT) to $AUTOPKG_PREFS"
fi

# ensure untrusted recipes fail (if not already set)
if ! ${DEFAULTS} read "$AUTOPKG_PREFS" FAIL_RECIPES_WITHOUT_TRUST_INFO >/dev/null 2>&1 ; then
    ${DEFAULTS} write "$AUTOPKG_PREFS" FAIL_RECIPES_WITHOUT_TRUST_INFO -bool true
    ${LOGGER} "Wrote FAIL_RECIPES_WITHOUT_TRUST_INFO 'true' to $AUTOPKG_PREFS"
    echo
    echo "   [setup] Wrote FAIL_RECIPES_WITHOUT_TRUST_INFO 'true' to $AUTOPKG_PREFS"
fi

# read in parameters
if [[ "$JSS_URL" ]]; then
    ${DEFAULTS} write "$AUTOPKG_PREFS" JSS_URL "$JSS_URL"
    ${LOGGER} "Wrote JSS_URL: '$JSS_URL' to $AUTOPKG_PREFS"
    echo
    echo "   [setup] Wrote JSS_URL: '$JSS_URL' to $AUTOPKG_PREFS"
fi
if ! ${DEFAULTS} read "$AUTOPKG_PREFS" JSS_URL >/dev/null 2>&1 ; then
    read -r -p "JSS URL: " JSS_URL
    ${LOGGER} "Wrote JSS_URL: '$JSS_URL' to $AUTOPKG_PREFS"
    echo
    echo "   [setup] Wrote JSS_URL: '$JSS_URL' to $AUTOPKG_PREFS"
    ${DEFAULTS} write "$AUTOPKG_PREFS" JSS_URL "$JSS_URL"
fi

if [[ "$API_USERNAME" ]]; then
    ${DEFAULTS} write "$AUTOPKG_PREFS" API_USERNAME "$API_USERNAME"
    ${LOGGER} "Wrote API_USERNAME: '$API_USERNAME' to $AUTOPKG_PREFS"
    echo
    echo "   [setup] Wrote API_USERNAME: '$API_USERNAME' to $AUTOPKG_PREFS"
fi
if ! ${DEFAULTS} read "$AUTOPKG_PREFS" API_USERNAME >/dev/null 2>&1 ; then
    read -r -p "JSS API user: " API_USERNAME
    ${DEFAULTS} write "$AUTOPKG_PREFS" API_USERNAME "$API_USERNAME"
    ${LOGGER} "Wrote API_USERNAME: '$API_USERNAME' to $AUTOPKG_PREFS"
    echo
    echo "   [setup] Wrote API_USERNAME: '$API_USERNAME' to $AUTOPKG_PREFS"
fi

if [[ "$API_PASSWORD" ]]; then
    ${DEFAULTS} write "$AUTOPKG_PREFS" API_PASSWORD "$API_PASSWORD"
    ${LOGGER} "Wrote API_PASSWORD: '(redacted)' to $AUTOPKG_PREFS"
    echo
    echo "   [setup] Wrote API_PASSWORD: '(redacted)' to $AUTOPKG_PREFS"
fi
if ! ${DEFAULTS} read "$AUTOPKG_PREFS" API_PASSWORD >/dev/null 2>&1 ; then
    read -r -s -p "JSS API user's password: " API_PASSWORD
    ${DEFAULTS} write "$AUTOPKG_PREFS" API_PASSWORD "$API_PASSWORD"
    ${LOGGER} "Wrote API_PASSWORD: '(redacted)' to $AUTOPKG_PREFS"
    echo
    echo "   [setup] Wrote API_PASSWORD: '(redacted)' to $AUTOPKG_PREFS"
fi

if [[ "$SMB_URL" ]]; then
    ${DEFAULTS} write "$AUTOPKG_PREFS" SMB_URL "$SMB_URL"
    ${LOGGER} "Wrote SMB_URL: '$SMB_URL' to $AUTOPKG_PREFS"
    echo
    echo "   [setup] Wrote SMB_URL: '$SMB_URL' to $AUTOPKG_PREFS"
fi
if ! ${DEFAULTS} read "$AUTOPKG_PREFS" SMB_URL >/dev/null 2>&1 ; then
    if [[ $smb_repo == "yes" ]]; then
        read -r -p "SMB URL: " SMB_URL
        if [[ "$SMB_URL" != "" ]]; then
            ${DEFAULTS} write "$AUTOPKG_PREFS" SMB_URL "$SMB_URL"
        ${LOGGER} "Wrote SMB_URL: '$SMB_URL' to $AUTOPKG_PREFS"
        echo
        echo "   [setup] Wrote SMB_URL: '$SMB_URL' to $AUTOPKG_PREFS"
        fi
    fi
fi

if [[ "$SMB_USERNAME" ]]; then
    ${DEFAULTS} write "$AUTOPKG_PREFS" SMB_USERNAME "$SMB_USERNAME"
    ${LOGGER} "Wrote SMB_USERNAME: '$SMB_USERNAME' to $AUTOPKG_PREFS"
    echo
    echo "   [setup] Wrote SMB_USERNAME: '$SMB_USERNAME' to $AUTOPKG_PREFS"
fi
if ! ${DEFAULTS} read "$AUTOPKG_PREFS" SMB_USERNAME >/dev/null 2>&1 ; then
    if ${DEFAULTS} read "$AUTOPKG_PREFS" SMB_URL >/dev/null 2>&1 ; then
        read -r -p "SMB username: " SMB_USERNAME
        ${DEFAULTS} write "$AUTOPKG_PREFS" SMB_USERNAME "$SMB_USERNAME"
        ${LOGGER} "Wrote SMB_USERNAME: '$SMB_USERNAME' to $AUTOPKG_PREFS"
        echo
        echo "   [setup] Wrote SMB_USERNAME: '$SMB_USERNAME' to $AUTOPKG_PREFS"
    fi
fi

if [[ "$SMB_PASSWORD" ]]; then
    ${DEFAULTS} write "$AUTOPKG_PREFS" SMB_PASSWORD "$SMB_PASSWORD"
    ${LOGGER} "Wrote SMB_PASSWORD: '(redacted)' to $AUTOPKG_PREFS"
    echo
    echo "   [setup] Wrote SMB_PASSWORD: '(redacted)' to $AUTOPKG_PREFS"
fi
if ! ${DEFAULTS} read "$AUTOPKG_PREFS" SMB_PASSWORD >/dev/null 2>&1; then
    if ${DEFAULTS} read "$AUTOPKG_PREFS" SMB_URL >/dev/null 2>&1 ; then
        read -r -s -p "SMB password: " SMB_PASSWORD
        ${DEFAULTS} write "$AUTOPKG_PREFS" SMB_PASSWORD "$SMB_PASSWORD"
        ${LOGGER} "Wrote SMB_PASSWORD: '(redacted)' to $AUTOPKG_PREFS"
        echo
        echo "   [setup] Wrote SMB_PASSWORD: '(redacted)' to $AUTOPKG_PREFS"
    fi
fi

# add Slack credentials if anything supplied
if [[ $SLACK_USERNAME || $SLACK_WEBHOOK ]]; then
    configureSlack
fi

## AutoPkg repos:
# grahampugh-recipes required for JamfUploader processors.
# Add more recipe repos here if required.
if [[ -f "$AUTOPKG_REPO_LIST" ]]; then
    read -r -d '' AUTOPKGREPOS < "$AUTOPKG_REPO_LIST"
else
    read -r -d '' AUTOPKGREPOS <<ENDMSG
grahampugh-recipes
ENDMSG
fi

# ensure all repos associated with an inputted recipe list are added
# note this will only get missing repos of parent recipes, not of recipes themselves
if [[ -f "$AUTOPKG_RECIPE_LIST" ]]; then
    while read -r recipe ; do 
        ${AUTOPKG} info -p "${recipe}" --prefs "$AUTOPKG_PREFS"
    done < "$AUTOPKG_RECIPE_LIST"
fi

# Add AutoPkg repos (checks if already added)
${AUTOPKG} repo-add "${AUTOPKGREPOS}" --prefs "$AUTOPKG_PREFS"

# Update AutoPkg repos (if the repos were already there no update would otherwise happen)
${AUTOPKG} repo-update all --prefs "$AUTOPKG_PREFS"

${LOGGER} "AutoPkg Repos Configured"
echo
echo "   [setup] AutoPkg Repos Configured"

