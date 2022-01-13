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

ros_management_remove_paths()
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
ros_management_remove_all_paths()
{
    export AMENT_PREFIX_PATH=$(ros_management_remove_paths "$AMENT_PREFIX_PATH" $@)
    export AMENT_CURRENT_PREFIX=$(ros_management_remove_paths "$AMENT_CURRENT_PREFIX" $@)
    export PYTHONPATH=$(ros_management_remove_paths "$PYTHONPATH" $@)
    export CMAKE_PREFIX_PATH=$(ros_management_remove_paths "$CMAKE_PREFIX_PATH" $@)
    export PATH=$(ros_management_remove_paths "$PATH" $@)
    export LD_LIBRARY_PATH=$(ros_management_remove_paths "$LD_LIBRARY_PATH" $@)
}

# Register a single ROS 1 / 2 workspace, try to source in order : ws > ws/install > ws/devel
ros_management_register_workspace()
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
ros_management_remove_all_paths $ros2_workspaces
unset ROS_DISTRO

# register ROS 1 workspaces
local ws
for ws in $ros1_workspaces
do
    ros_management_register_workspace $ws
done
for ws in $ros1_workspaces
do
    ros_management_register_workspace $ws
done
# change prompt if you like (actually not by default)
local ROS1_COLOR="29"   # noetic green
export PS1="$PS1_ori"
# PS1="\e[38;5;${ROS1_COLOR}m[ROS1] $PS1_ori"
if [ -f /usr/share/gazebo/setup.sh ]; then
    source /usr/share/gazebo/setup.sh
fi
}

# Activate ROS 2 ws
ros2ws()
{
# Clean ROS 1 paths
ros_management_remove_all_paths $ros1_workspaces
unset ROS_DISTRO

# register ROS 2 workspaces
local ws
for ws in $ros2_workspaces
do
    ros_management_register_workspace $ws
done

# add base ROS 1 libs in case some ROS 2 pkg need them
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/ros/noetic/lib

# change prompt
local ROS2_COLOR="166"  # foxy orange
export PS1="\e[38;5;${ROS2_COLOR}m[ROS2] $PS1_ori"
if [ -f /usr/share/gazebo/setup.sh ]; then
    source /usr/share/gazebo/setup.sh
fi
}

# some shortcuts
colbuild()
{
# Clean ROS 1 paths
ros_management_remove_all_paths $ros1_workspaces
unset ROS_DISTRO

# source ROS 2 ws up to this one
unset AMENT_PREFIX_PATH
unset AMENT_CURRENT_PREFIX
unset COLCON_PREFIX_PATH

local ws
local PWD="$(pwd)/"
for ws in $ros2_workspaces; do

    # if in this workspace, run colcon
    if [[ "$PWD" = "$ws/"* ]]; then
        local cmd="colcon build --symlink-install --continue-on-error $@"
        if [ -d "$ws/src/ros1_bridge" ]; then
            cmd="$cmd  --packages-skip ros1_bridge"
        fi
        (cd $ws;eval $cmd)
    fi
    # source anyway
    ros_management_register_workspace $ws
done
}

# restrict fastrtps / Cyclone DDS to this network interface
rmw_restrict()
{

# if interface is given, update file
if [[ $# -eq 1 ]]; then

    # fastRTPS https://fast-dds.docs.eprosima.com/en/latest/fastdds/transport/whitelist.html
    echo "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>
    <profiles xmlns=\"http://www.eprosima.com/XMLSchemas/fastRTPS_Profiles\">
        <transport_descriptors>
            <transport_descriptor>
                <transport_id>CustomUDPTransport</transport_id>
                <type>UDPv4</type>
                <interfaceWhiteList>
                    <address>$1</address>
                </interfaceWhiteList>
            </transport_descriptor>
        </transport_descriptors>
        <participant profile_name=\"CustomUDPTransportParticipant\">
            <rtps>
                <userTransports>
                    <transport_id>CustomUDPTransport</transport_id>
                </userTransports>
            </rtps>
        </participant>
    </profiles>" > /tmp/fastrtps_interface_restriction.xml

    # Cyclone DDS https://dds-demonstrators.readthedocs.io/en/latest/Teams/1.Hurricane/setupCycloneDDS.html
    echo " <?xml version=\"1.0\" encoding=\"UTF-8\" ?>
    <CycloneDDS xmlns=\"https://cdds.io/config\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:schemaLocation=\"https://cdds.io/config https://raw.githubusercontent.com/eclipse-cyclonedds/cyclonedds/master/etc/cyclonedds.xsd\">
        <Domain id=\"any\">
            <General>
                <NetworkInterfaceAddress>$1</NetworkInterfaceAddress>
            </General>
        </Domain>
    </CycloneDDS>" > /tmp/cyclonedds_interface_restriction.xml
fi

# in all case, source these files
export FASTRTPS_DEFAULT_PROFILES_FILE=/tmp/fastrtps_interface_restriction.xml
export CYCLONEDDS_URI=/tmp/cyclonedds_interface_restriction.xml
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
ros_management_remove_all_paths "$ros1_workspaces $ros2_workspaces"
unset ROS_DISTRO
# register ROS 2 overlays before the ros1_bridge overlay
colbuild

# register base ROS 1 installation
unset ROS_DISTRO
local ros1_base=${ros1_workspaces% *}
ros_management_register_workspace $ros1_base
# register base ROS 2 installation
unset ROS_DISTRO
local ros2_base=${ros2_workspaces% *}
ros_management_register_workspace $ros2_base

# register ROS 1 overlays
unset ROS_DISTRO
for ws in $ros1_workspaces; do
    if [[ "$ws" != "$ros1_base" ]]; then
        ros_management_register_workspace $ws
    fi
done

# register ROS 2 overlays up to the ros1_bridge overlay
unset ROS_DISTRO
for ws in "$ros2_workspaces"; do
    if [[ "$ws" != "$ros2_base" ]]; then
       ros_management_register_workspace $ws
       if [[ "$ws" = "$bridge_overlay"* ]]; then
       break
       fi
    fi
done
colcon build --symlink-install --packages-select ros1_bridge --cmake-force-configure --continue-on-error
}


fastdds_server()
{
fastdds discovery --server-id 0
}

# enable fastdds discovery server if running
if pgrep fast-discovery- > /dev/null
then
    export ROS_DISCOVERY_SERVER=127.0.0.1:11811
#     echo "[ROS2] Enabling fast-discovery-server"
fi
