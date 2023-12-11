#!/usr/bin/env bash


ROS_MANAGEMENT_DEST=$(pwd)
ROS_MANAGEMENT_OPT="-ros2 -p -k -lo"
ROS_MANAGEMENT_SKEL=0
ROS_MANAGEMENT_YES=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
    echo "options:
    -d / --dest <directory> (default current dir): destination directory
    -o / --opt <options> (default $ROS_MANAGEMENT_OPT):  manager option
    -s / --skel (default false): setup /etc/skel/.bashrc
    -y / --yes (default false): skip confirmation"
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
      shift
      ;;
    -d|--dest)
      ROS_MANAGEMENT_DEST="$2"
      shift # past argument
      shift # past value
      ;;
    -o|--opt)
      ROS_MANAGEMENT_OPT="$2"
      shift # past argument
      shift # past value
      ;;
    -s|--skel)
      ROS_MANAGEMENT_SKEL=1
      shift # past argument
      ;;
    -y|--yes)
      ROS_MANAGEMENT_YES=1
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

need_sudo="(requires sudo)"

if [[ "$ROS_MANAGEMENT_DEST" == "$HOME"* ]]; then
  need_sudo=""
fi

echo "Will install with the following setup:"
echo "   - options: $ROS_MANAGEMENT_OPT"
echo "   - dest: $ROS_MANAGEMENT_DEST $need_sudo"
if [[ $ROS_MANAGEMENT_SKEL -eq "1" ]]; then
  echo "   - skeleton: forward to /etc/skel/.bashrc (requires sudo)"
fi

if [[ -z $ROS_MANAGEMENT_YES ]]; then
  read -p "Proceed with installation? [Y/n] " -n 1 -r
  echo    # (optional) move to a new line
  if [[ ! -z $REPLY ]] && [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "installation cancelled"
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
  fi
fi

echo "Installing..."

# copy to destination if not default
ROS_MANAGEMENT_ROOT=$(pwd)
if [[ "$ROS_MANAGEMENT_DEST" != "$(pwd)" ]]; then
  ROS_MANAGEMENT_ROOT=$ROS_MANAGEMENT_DEST/ros_management
  # use sudo if required
  if [[ -z "$need_sudo" ]]; then
    mkdir -p $ROS_MANAGEMENT_DEST
    cp -r . $ROS_MANAGEMENT_DEST
    else
    sudo mkdir -p $ROS_MANAGEMENT_DEST
    sudo cp -r . $ROS_MANAGEMENT_DEST
    sudo chmod a+r $ROS_MANAGEMENT_DEST
    fi
fi

CMD="$ROS_MANAGEMENT_ROOT/ros_management.bash $ROS_MANAGEMENT_OPT"

# function that replaces the line in given file if it exists, otherwise appends it
function replace_or_append
{
  local file=$1
  local CMD="source ${@:2}"
  local line=$(grep "ros_management.bash" $file)
  if [[ -z $line ]]; then
    echo "Adding source ros_management.bash to $file"
    echo "$CMD" >> $file
  elif [[ "$line" != "$CMD" ]]; then
    echo "Updating source ros_management.bash to $file"
    sed -i "s|$line|$CMD|g" $file
  else
    echo "$file already up-to-date"
  fi
}

# call on .bashrc anyway
CMD="$ROS_MANAGEMENT_ROOT/ros_management.bash $ROS_MANAGEMENT_OPT"
replace_or_append ~/.bashrc $CMD

# do the same in /etc/skel/.bashrc if requested
if [[ $ROS_MANAGEMENT_SKEL -eq "1" ]]; then
  FUNC=$(declare -f replace_or_append)
  sudo bash -c "$(declare -f replace_or_append); replace_or_append /etc/skel/.bashrc $CMD"
fi

echo "Installation complete"

echo "Do not forget to define the 'ros1_workspaces' and/or 'ros2_workspaces' environment variables in the .bashrc before sourcing this script."
