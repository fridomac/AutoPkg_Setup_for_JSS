#!/usr/bin/python

"""
install_autopkg.py

Downloads and installs AutoPkg.
"""

import os
import requests
import subprocess
import json
import yaml as pyyaml
from plistlib import writePlistToString


def read_plist(plist):
    """Converts binary plist to json and then imports the content as a dict"""
    content = plist.read()
    args = ["plutil", "-convert", "json", "-o", "-", "--", "-"]
    proc = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    out, err = proc.communicate(content)
    return json.loads(out)


def convert_to_plist(yaml):
    """Converts dict to plist format"""
    lines = writePlistToString(yaml).splitlines()
    lines.append('')
    return "\n".join(lines)


def check_not_sudo():
    """this script must run as a regular user who will be called to supply their password"""
    uid = os.getuid()
    if uid == 0:
        print ("This script cannot be run as root!\n"
               "Please re-run the script as the regular user")
        exit(1)
    else:
        print ("This script requires administrator rights to install autopkg.\n"
               "Please enter your password if prompted")


def run_live(c):
    """Run a subprocess with real-time output.
    Returns only the return-code."""
    # Validate that command is not a string
    if isinstance(c, basestring): # Not an array!
        raise TypeError('Command must be an array')

    # Run the command
    proc = subprocess.Popen(c, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (c_out, c_err) = proc.communicate()
    if c_out:
        print "Result:\n%s" % c_out
    if c_err:
        print "Error:\n%s" % c_err


def get_download_url(url):
    """get download URL from releases page"""
    r = requests.get(url)
    if r.status_code != 200:
        raise ValueError(
            'Request returned an error %s, the response is:\n%s'
            % (r.status_code, r.text)
        )
    obj = r.json()
    browser_download_url = obj[0]["assets"][0]["browser_download_url"]
    return browser_download_url


def download(url, download_path):
    """get it"""
    r = requests.get(url)
    if r.status_code != 200:
        raise ValueError(
            'Request returned an error %s, the response is:\n%s'
            % (r.status_code, r.text)
        )
    with open(download_path, 'wb') as f:
        f.write(r.content)


def add_repo(repo):
    """Adds an AutoPkg recipe repo"""
    cmd = ['/usr/local/bin/autopkg', 'repo-add', repo]
    run_live(cmd)


def add_private_repo(repo, url, autopkg_prefs):
    """Adds a private AutoPkg recipe repo"""
    # clone the recipe repo if it isn't there already
    plistbuddy="/usr/libexec/PlistBuddy"

    repo_path = os.path.join('~/Library/AutoPkg/RecipeRepos/', repo)
    if not os.path.isdir(repo_path):
        cmd = ['/usr/bin/git', 'clone', url, repo_path]
        run_live(cmd)

        # add to AutoPkg prefs RECIPE_REPOS
        # First check if it's already there - we can leave it alone if so!
        cmd = [plistbuddy, '-c', 'Print :RECIPE_REPOS:{}'.format(repo_path), autopkg_prefs]
        stdout = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE).communicate[0]
        if not stdout:
            cmd = [plistbuddy, '-c', 'Add :RECIPE_REPOS:{} dict'.format(repo_path), autopkg_prefs]
            run_live(cmd)
            cmd = [plistbuddy, '-c', 'Add :RECIPE_REPOS:{}:URL string {}'.format(repo_path, url), autopkg_prefs]
            run_live(cmd)

        # add to AutoPkg prefs RECIPE_SEARCH_DIRS
        cmd = [plistbuddy, '-c', 'Print :RECIPE_SEARCH_DIRS', autopkg_prefs]
        stdout = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE).communicate[0]
        if not repo_path in stdout:
            cmd = [plistbuddy, '-c', 'Add :RECIPE_REPOS:{} dict'.format(repo_path), autopkg_prefs]
            run_live(cmd)
            cmd = [plistbuddy, '-c', 'Add :RECIPE_SEARCH_DIRS: string {}'.format(repo_path), autopkg_prefs]
            run_live(cmd)


def update_repos():
    """Update any existing AutoPkg recipe repos"""
    cmd = ['/usr/local/bin/autopkg', 'repo-update', 'all']
    run_live(cmd)


def remove_download(download_path):
    """remove the downloaded pkg"""
    try:
        os.remove(download_path)
    except:
        pass


def set_autopkg_prefs(autopkg_prefs_file=None):
    # grab credentials from yaml file
    try:
        autopkg_prefs_file = os.path.join(os.getcwd(), autopkg_prefs_file)
        print "Inputted prefs file: {}".format(autopkg_prefs_file)
    except UnboundLocalError:
        autopkg_prefs_file = os.path.join(os.getcwd(), "autopkg-preferences.yaml")
        print "Inputted prefs file: {}".format(autopkg_prefs_file)
    if os.path.isfile(autopkg_prefs_file):
        in_file = open(autopkg_prefs_file, 'r')
        input = pyyaml.safe_load(in_file)

        autopkg_prefs           = input['AUTOPKG_PREFS_LOCATION']
        jss_url                 = input['JSS_URL']
        api_username            = input['API_USERNAME']
        api_password            = input['API_PASSWORD']
        jss_repos               = input['JSS_REPOS']
        private_repos           = input['PRIVATE_REPOS']

        autopkg_prefs_path = os.path.expanduser(autopkg_prefs)
        prefs_file = open(autopkg_prefs_path, 'r')
        prefs_data = read_plist(prefs_file)
        prefs_file.close()
        if jss_url:
            prefs_data['JSS_URL'] = jss_url
        if api_username:
            prefs_data['API_USERNAME'] = api_username
        if api_password:
            prefs_data['API_PASSWORD'] = api_password
        if jss_repos:
            for i in range(0, len(jss_repos)):
                print jss_repos[i]
                if 'type' in jss_repos[i]:
                    prefs_data['JSS_REPOS'][i]['type'] = jss_repos[i]['type']
                elif 'name' in jss_repos[i]:
                    try:
                        prefs_data['JSS_REPOS'][i]['name'] = jss_repos[i]['name']
                        prefs_data['JSS_REPOS'][i]['password'] = jss_repos[i]['password']
                    except KeyError:
                        prefs_data['JSS_REPOS'] = {}
                        prefs_data['JSS_REPOS'][i] = dict()
                        prefs_data['JSS_REPOS'][i]['name'] = jss_repos[i]['name']
                        prefs_data['JSS_REPOS'][i]['password'] = jss_repos[i]['password']
        # if private_repos:
        #     for x in range(0, len(private_repos)-1):
        #         if private_repos[p]['url']:
        #             add_private_repo(private_repos[p]['dir'],
        #                              private_repos[p]['url'], autopkg_prefs)

        print prefs_data
        output = convert_to_plist(prefs_data)
        prefs_file = open(autopkg_prefs_path, 'w')
        prefs_file.writelines(output)
        prefs_file.close()
        print "Updated AutoPkg preferences"

        # except:
        #     print "AutoPkg preferences could not be created."
        #     exit(1)

    else:
        print "No autopkg_prefs_file found. Will attempt to continue with default prefs."


def install_autopkg(autopkg_prefs_file=None, repo_list=None):
    """install it"""
    url = 'https://api.github.com/repos/autopkg/autopkg/releases'
    download_path = '/tmp/autopkg-latest.pkg'

    # check script is not running as root
    check_not_sudo()

    # grab the download url
    url = get_download_url(url)

    # do the download
    download(url, download_path)

    # do the install
    cmd = ["/usr/bin/sudo", "/usr/sbin/installer", "-pkg", download_path, "-target", "/"]
    run_live(cmd)

    # remove download
    remove_download(download_path)

    # add repos if there is a list
    try:
        with open(os.path.join(os.getcwd(), repo_list)) as f:
            repos = f.readlines()
            repos = [x.strip() for x in repos] # strips newline characters
    except UnboundLocalError:
        print "No repo file"

    # add repos from autopkg-repo-list.txt
    for repo in repos:
        add_repo(repo)

    # set config
    set_autopkg_prefs(autopkg_prefs_file)

    # update repos (this duplication is for repos that were already present)
    update_repos()




def main():
    """do the main thing"""
    autopkg_prefs_file = os.path.join(os.pardir, "autopkg-preferences.yaml")
    repo_list = os.path.join(os.pardir, "autopkg-repo-list.txt")
    install_autopkg(autopkg_prefs_file, repo_list)





if __name__ == '__main__':
    main()
