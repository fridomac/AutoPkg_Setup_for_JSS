#!/usr/bin/python

"""
install_jssimporter.py

Downloads and installs JSS Importer.
For now we use the AuoPkg recipe.

Elements of this script from:
https://github.com/facebook/IT-CPE/blob/master/autopkg_tools/autopkg_tools.py
"""

import os
import subprocess
from install_autopkg import run_live
from install_autopkg import add_repo
from install_autopkg import download


def make_override(recipe):
    """Makes an override for a recipe"""
    cmd = ['/usr/local/bin/autopkg', 'make-override', recipe]
    run_live(cmd)


def run_recipe(recipe, report_plist_path=None, pkg_path=None):
    """
    Executes autopkg on a recipe, creating report plist.
    Taken from https://github.com/facebook/IT-CPE/blob/master/autopkg_tools/autopkg_tools.py
    """
    cmd = ['/usr/local/bin/autopkg', 'run', '-v']
    cmd.append(recipe)
    if pkg_path:
        cmd.append('-p')
        cmd.append(pkg_path)
    if report_plist_path:
        cmd.append('--report-plist')
        cmd.append(report_plist_path)
    run_live(cmd)


def install_jssimporter():
    """Installs JSSImporter using AutoPkg"""
    # install JSSImporter
    add_repo('grahampugh/recipes')
    make_override('JSSImporterBeta.install')
    run_recipe('JSSImporterBeta.install')

    # temporarily get latest version directly from GitHub
    jssimporterpy_beta_url = 'https://raw.githubusercontent.com/grahampugh/JSSImporter/testing/JSSImporter.py'
    tmp_location = '/tmp/JSSImporter.py'
    jssimporterpy_location = '/Library/AutoPkg/autopkglib/JSSImporter.py'
    download(jssimporterpy_beta_url, tmp_location)
    cmd = ["/usr/bin/sudo", "mv", tmp_location, jssimporterpy_location]
    run_live(cmd)
    print "Installed latest JSSImporter"


def main():
    """Does the main thing"""
    install_jssimporter()


if __name__ == '__main__':
    main()
