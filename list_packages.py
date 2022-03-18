#!/bin/env python3

from subprocess import check_output
import sys

ros_prefix = 'ros-'
if len(sys.argv) > 1 and not sys.argv[1].startswith('-'):
    ros_prefix += sys.argv[1]    
    
single_row = '-r' in sys.argv
    
pkgs = check_output('apt list --installed' .split()).decode().splitlines()
pkgs = [p.split('/')[0] for p in pkgs if p.startswith(ros_prefix) and ',automatic' not in p]

if single_row:
    print(' '.join(pkgs))
else:
    print('\n'.join(pkgs))

