#!/bin/env python3

from subprocess import Popen, check_output, PIPE
import sys
import argparse

'''
List packages installed for a ROS distro, list if they can be installed with another distro
'''

parser = argparse.ArgumentParser(formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument('-d','--distro', type=str, help='Any specific distro', default='')
parser.add_argument('-r','--row', action='store_true', help='Display in row',default=False)
parser.add_argument('-R','--replace', type=str, help='Print same list with new distro',default='')

args = parser.parse_args()

ros_prefix = 'ros-' + args.distro

pkgs = check_output('apt list --installed' .split()).decode().splitlines()
pkgs = [p.split('/')[0] for p in pkgs if p.startswith(ros_prefix) and ',automatic' not in p]

missing = []
if args.replace and args.distro:
    pkgs = [p.replace(args.distro, args.replace) for p in pkgs]
    # test which cannot be installed
    apt = Popen('apt install --simulate'.split() + pkgs, stdout=PIPE, stderr=PIPE)
    output, error = apt.communicate()
    error = error.decode().splitlines()
    if error:
        missing = [line.split()[-1] for line in error if line.startswith('E: Unable')]
        for p in missing:
            pkgs.remove(p)

if args.row:
    print(' '.join(pkgs))
else:
    print('\n'.join(pkgs))

if len(missing):
    print('\nNot installable:', ' '.join(missing))
