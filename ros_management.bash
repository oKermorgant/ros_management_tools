#!/bin/bash

# Switch between ROS 1 / ROS 2 workspaces without messing with environment variables
# Olivier Kermorgant

# ROS 1 / 2 workspaces are defined in overlay ordering 
# ex: ros1_workspaces="/opt/ros/noetic $HOME/ros_ws1 $HOME/ros_ws2"

# Takes a path string separated with colons and a list of sub-paths
# Removes path elements containing sub-paths

# replace tilde by home dir in paths
export ros1_workspaces="${ros1_workspaces//'~'/$HOME}"
export ros2_workspaces="${ros2_workspaces//'~'/$HOME}"
export PS1_ori=$PS1

remove_paths()
{
IFS=':' read -ra PATHES <<< "$1"
local THISPATH=""
local path
for path in "${PATHES[@]}"; do
  local to_remove=0
  local i
  for (( i=2; i <="$#"; i++ )); do
    if [[ $path = *"${!i}"* ]]; then
       to_remove=1
       break
    fi
  done
  if [ $to_remove -eq 0 ]; then
    THISPATH="$THISPATH:$path"
  fi
done
echo $THISPATH | cut -c2-
}

# Takes a list of sub-paths
# Updates ROS-related system paths by removing all elements containing sub-paths
remove_all_paths()
{
    export AMENT_PREFIX_PATH=$(remove_paths "$AMENT_PREFIX_PATH" $@)
    export AMENT_CURRENT_PREFIX=$(remove_paths "$AMENT_CURRENT_PREFIX" $@)
    export PYTHONPATH=$(remove_paths "$PYTHONPATH" $@)
    export CMAKE_PREFIX_PATH=$(remove_paths "$CMAKE_PREFIX_PATH" $@)
    export PATH=$(remove_paths "$PATH" $@)
    export LD_LIBRARY_PATH=$(remove_paths "$LD_LIBRARY_PATH" $@)
}

# Register a single ROS 1 / 2 workspace, try to source in order : ws > ws/install > ws/devel
register_ros_workspace()
{
local subs="/ /install/ /devel/"
local sub
for sub in $subs
do
    if [ -f "$1${sub}local_setup.bash" ]; then
            source "$1${sub}local_setup.bash"
        return
    fi
done
}

# Equivalent of roscd but jumps to the source (also, no completion)
ros2cd()
{
local ws=$ros2_workspaces
local prev=""
local subs="/src /install /devel /"
local sub
local key="<name>$1</name>"
local res
while [ "$ws" != "$prev" ]
do
    # Make it to the source directory if possible
    for sub in $subs
    do
    if [ -d "${ws##* }$sub" ]; then
        res=$(grep -r --include \*package.xml $key ${ws##* }$sub )
        if [[ $res != "" ]]; then 
        cd ${res%%/package.xml*}
        return
        fi
    fi
    done
    prev="$ws"
    ws="${ws% *}"
done
echo "Could not find package $1"
}

# Activate ROS 1 ws
ros1ws()
{
# Clean ROS 2 paths
remove_all_paths $ros2_workspaces
unset ROS_DISTRO

# register ROS 1 workspaces
local ws
for ws in $ros1_workspaces
do
    register_ros_workspace $ws
done
for ws in $ros1_workspaces
do
    register_ros_workspace $ws
done
# change prompt if you like (actually not by default)
local ROS1_COLOR="29"   # noetic green
export PS1="$PS1_ori"
# PS1="\e[38;5;${ROS1_COLOR}m[ROS1] $PS1_ori"
source /usr/share/gazebo/setup.sh
}

# Activate ROS 2 ws
ros2ws()
{
# Clean ROS 1 paths
remove_all_paths $ros1_workspaces
unset ROS_DISTRO

# register ROS 2 workspaces
local ws
for ws in $ros2_workspaces
do
    register_ros_workspace $ws
done
# change prompt
local ROS2_COLOR="166"  # foxy orange
export PS1="\e[38;5;${ROS2_COLOR}m[ROS2] $PS1_ori"
source /usr/share/gazebo/setup.sh
}

# some shortcuts
colbuild()
{
# Clean ROS 1 paths
remove_all_paths $ros1_workspaces
unset ROS_DISTRO
# source ROS 2 ws up to this one
unset AMENT_PREFIX_PATH
unset AMENT_CURRENT_PREFIX
unset COLCON_PREFIX_PATH

local ws
local PWD="$(pwd)/"
for ws in $ros2_workspaces; do
    if [[ "$PWD" = "$ws/"* ]]; then
      break
    fi
    register_ros_workspace $ws
done

local cmd="colcon build --symlink-install --continue-on-error $@"
if [ -d "src/ros1_bridge" ]; then
    cmd="$cmd  --packages-skip ros1_bridge"
fi
# cd $ws
(ros2ws;cd $ws;eval $cmd)
# eval $cmd
# cd $PWD
ros2ws
}

# shortcut to be sure where we are
alias rosd='echo $ROS_DISTRO'

# shortcut to build ros1_bridge without messing system paths
# assumes we are in our ROS 2 workspace directory / recompiles ros1_bridge
# make sure it is worth it, this is quite long...
ros1bridge_recompile()
{
if [ ! -d "src/ros1_bridge" ]; then
    echo "ros1_bridge is not in this workspace - is it actually a ROS 2 workspace?"
    return
fi
# clean environment variables
remove_all_paths "$ros1_workspaces $ros2_workspaces"
unset ROS_DISTRO
# register ROS 2 overlays before the ros1_bridge overlay
colbuild

# register base ROS 1 installation
unset ROS_DISTRO
local ros1_base=${ros1_workspaces% *}
register_ros_workspace $ros1_base
# register base ROS 2 installation
unset ROS_DISTRO
local ros2_base=${ros2_workspaces% *}
register_ros_workspace $ros2_base

# register ROS 1 overlays
unset ROS_DISTRO
for ws in $ros1_workspaces; do
    if [[ "$ws" != "$ros1_base" ]]; then
        register_ros_workspace $ws
    fi
done

# register ROS 2 overlays up to the ros1_bridge overlay
unset ROS_DISTRO
for ws in "$ros2_workspaces"; do
    if [[ "$ws" != "$ros2_base" ]]; then
       register_ros_workspace $ws
       if [[ "$ws" = "$bridge_overlay"* ]]; then
       break
       fi
    fi
done
colcon build --symlink-install --packages-select ros1_bridge --cmake-force-configure --continue-on-error
}
