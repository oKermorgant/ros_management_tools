#!/usr/bin/env bash


ROS_MANAGEMENT_DEST=$(pwd)
ROS_MANAGEMENT_OPT="-ros2 -p -k"
ROS_MANAGEMENT_SKEL=0

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
    echo "options:
    -d / --dest <directory> (default $ROS_MANAGEMENT_DEST): destination directory (must be writable)
    -o / --opt <options> (default $ROS_MANAGEMENT_OPT):  manager option
    -s / --skel (default false): setup /etc/skel/.bashrc"
      shift
      ;;
    -d|--dest)
      ROS_MANAGEMENT_DEST="$2"
      shift # past argument
      shift # past value
      ;;
    -o|--opt)
      ROS_MANAGEMENT_DEST="$2"
      shift # past argument
      shift # past value
      ;;
    -s|--skel)
      ROS_MANAGEMENT_SKEL=1
      shift # past argument
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done
