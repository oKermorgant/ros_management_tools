#!/bin/bash

# Switch between ROS 1 / ROS 2 workspaces without messing with environment variables
# Helpers for colcon (colbuild) and network interfaces with ROS 2
# Olivier Kermorgant

# ROS 1 / 2 workspaces are defined in overlay ordering
# ex: ros1_workspaces="/opt/ros/noetic $HOME/ros_ws1 $HOME/ros_ws2"

# replace tilde by home dir in paths
export ros1_workspaces="${ros1_workspaces//'~'/$HOME}"
export ros2_workspaces="${ros2_workspaces//'~'/$HOME}"
export PS1_ori=$PS1

# store arguments to this script to be used in inner functions
ROS_MANAGEMENT_ARGS="$*"


# add a command for the next auto-init
ros_management_add()
{
    if [[ ! $ROS_MANAGEMENT_ARGS == *"-k"* ]]; then
        return
    fi

    if [[ ! -e ~/.ros_management_auto_init ]]; then
        echo "$*" > ~/.ros_management_auto_init
        return
    fi

    local ros_history=$(<~/.ros_management_auto_init)

    # only valid commands are ros1ws vs ros2ws and any ros_ (exclusive)
    if [[ "$*" == *"ws" ]]; then
        local updated=${ros_history/ros[12]ws/$*}
    else
        local updated=$(echo "$ros_history" | sed "s/ros_.*/$*/")
    fi

    if [[ $updated != $ros_history ]]; then
        echo "$updated" > ~/.ros_management_auto_init
    else
        if [[ "$updated" != *"$*"* ]]; then
            echo "$*" >> ~/.ros_management_auto_init
        fi
    fi
}

# add ROS info to the prompt in order to know what version we use
# also indicates on which robot we are working, if any
ros_management_prompt()
{
    if [[ $ROS_MANAGEMENT_ARGS != *"-p"* ]] || [[ -z $(which rosversion) ]]; then
        return
    fi

    local token_color="\[\e[39m\]"
    local distro=$(rosversion -d)

    # get sourced version, if any
    local default_ros="0"
    if [[ $ROS_MANAGEMENT_ARGS =~ (.*)(-ros)([12])(.*) ]]; then
        local default_ros="${BASH_REMATCH[3]}"
    fi

    # we disable the prompt for the version that was given in source (assumed to be the default/quiet version)
    if [[ $distro == "noetic" ]] || [[ $distro == "<unknown>" ]] || [[ $distro == "Debian" ]]; then
        if [[ $default_ros != "1" ]]; then
            local ROS_COLOR="\[\e[38;5;106m\]"  # noetic green
            local ROS_PROMPT="${ROS_COLOR}[ROS1"
        fi
    else
        if [[ $default_ros != "2" ]]; then
            local ROS_COLOR=$(
            case "$distro" in
                ("foxy") echo "166" ;;
                ("galactic") echo "87" ;;
                ("rolling") echo "40" ;;
                ("humble") echo "74" ;;
                (*) echo "255" ;;
            esac)
            local ROS_COLOR="\[\e[38;5;${ROS_COLOR}m\]"
            local ROS_PROMPT="${ROS_COLOR}[ROS2"
        fi
    fi

    # split current PS1
    if [[ "$PS1" =~ (.*\\\])(\[)(.*)(\]\\\[\\e\[0m\\\] )(.*) ]]; then
        local cur_prompt=${BASH_REMATCH[3]}
        # back to base PS1
        export PS1=${BASH_REMATCH[5]}
        # extract current special token, if any
        if [[ $cur_prompt == *"@"* ]]; then
            if [[ "$cur_prompt" =~ (ROS[12])(\\\[.*\\\])(@)(.*)(\\\[.*) ]]; then
                local token_color=${BASH_REMATCH[2]}
                local token=${BASH_REMATCH[4]}
            fi
        else
            # special token only
            if [[ $cur_prompt != "ROS"* ]]; then
                local token_color=${BASH_REMATCH[1]}
                local token=$cur_prompt
            fi
        fi
    fi

    if [[ "$1" != "__CLEAN" ]]; then

        if [[ $# -ne 0 ]]; then
            # override token
            local token=$1
            if [[ $# -eq 2 ]]; then
            # add this color
                local token_color="\[\e[38;5;$2m\]"
            fi
        fi
        if [[ ! -z $token ]]; then
            if [[ -z $ROS_PROMPT ]]; then
                local ROS_PROMPT="${token_color}[$token"
                unset ROS_COLOR
            else
                local ROS_PROMPT="$ROS_PROMPT${token_color}@$token"
            fi
        fi
    fi
    if [[ ! -z $ROS_PROMPT ]]; then
        export PS1="$ROS_PROMPT${ROS_COLOR}]\[\e[0m\] $PS1"
    fi
}

# Takes a path string separated with colons and a list of sub-paths
# Removes path elements containing sub-paths
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
    if [ -f "$1${sub}local_setup.sh" ]; then
        source "$1${sub}local_setup.sh"
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

# do a Bloom release for a given distro
bloom-auto()
{
    bloom-release --ros-distro $1 --track $1 $(basename $PWD) $2
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

if [ -f /usr/share/gazebo/setup.sh ]; then
    source /usr/share/gazebo/setup.sh
fi

# change prompt if you like (actually not by default)
if [[ $# -eq 0 ]]; then
    ros_management_prompt
    ros_management_add ros1ws
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


if [ -f /usr/share/gazebo/setup.sh ]; then
    source /usr/share/gazebo/setup.sh
fi


# update ROS prompt
if [[ $# -eq 0 ]]; then
    ros_management_prompt
    ros_management_add ros2ws
fi
}

# some shortcuts
colbuild()
{
# Clean ROS 1 paths
ros_management_remove_all_paths $ros1_workspaces
unset ROS_DISTRO

# source ROS 2 workspaces up to this one (not including)
unset AMENT_PREFIX_PATH
unset AMENT_CURRENT_PREFIX
unset COLCON_PREFIX_PATH

local ws
local PWD="$(pwd)/"
for ws in $ros2_workspaces; do

    # if in this workspace, run colcon
    if [[ "$PWD" = "$ws/"* ]]; then
        local cmd="colcon build --symlink-install --continue-on-error"
        # add all args, change -p to --packages-select
        for arg in $@; do
            if [[ "$arg" = "-p" ]]
            then
                cmd="$cmd --packages-select"
            else
                cmd="$cmd $arg"
            fi
        done

        if [ -d "$ws/src/ros1_bridge" ]; then
            cmd="$cmd  --packages-skip ros1_bridge"
        fi
        (cd $ws;eval $cmd)
    fi
    # source anyway
    ros_management_register_workspace $ws
done
}

# restrict FastRTPS / Cyclone DDS to this network interface
ros_restrict()
{
    if [[ $# -eq 0 ]]; then
        echo "ros_restrict: give a network interface"
        return
    fi
    
    if [[ $ROS_DISTRO == "foxy" ]] || [[ $ROS_DISTRO == "galactic" ]]; then
        local legacy_cyclonedds=1
    fi

    # auto-detect if basic name
    local interface=$1
    if [[ $1 == "WIFI" ]]; then
        local interface=$(for dev in /sys/class/net/*; do [ -e "$dev"/wireless ] && echo ${dev##*/}; done)
    fi
    if [[ $1 == "ETH" ]]; then
        local interface=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}')
        local interface=$(for dev in $interface; do [ ! -e /sys/class/net/"$dev"/wireless ] && echo ${dev##*/}; done)
    fi
    if [[ $1 == "lo" ]]; then
        export ROS_LOCALHOST_ONLY=1
        unset ROS_DOMAIN_ID
        unset FASTRTPS_DEFAULT_PROFILES_FILE
        # https://answers.ros.org/question/365051/using-ros2-offline-ros_localhost_only1/
        
        if [[ -n $legacy_cyclonedds ]]; then
        export CYCLONEDDS_URI='<General>
            <NetworkInterfaceAddress>lo</NetworkInterfaceAddress>
            <AllowMulticast>false</AllowMulticast>
        </General>
        <Discovery>
            <ParticipantIndex>auto</ParticipantIndex>
            <MaxAutoParticipantIndex>100</MaxAutoParticipantIndex>
            <Peers>
                <Peer address="localhost"/>
            </Peers>
        </Discovery>'
        else
        export CYCLONEDDS_URI='<General>
             <Interfaces>
                <NetworkInterface name="lo"/>
            </Interfaces>
            <AllowMulticast>false</AllowMulticast>
        </General>
        <Discovery>
            <ParticipantIndex>auto</ParticipantIndex>
            <MaxAutoParticipantIndex>100</MaxAutoParticipantIndex>
            <Peers>
                <Peer address="localhost"/>
            </Peers>
        </Discovery>'
        fi

        # only update history and prompt if raw call
        if [[ $# -eq 1 ]]; then
            ros_management_add ros_restrict $interface
            ros_management_prompt __CLEAN
        fi
        return
    fi

    # Fast-DDS https://fast-dds.docs.eprosima.com/en/latest/fastdds/transport/whitelist.html
    # needs actual ip for this interface
    ipinet="$(ip a s $interface | egrep -o 'inet [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')"
    echo "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>
    <profiles xmlns=\"http://www.eprosima.com/XMLSchemas/fastRTPS_Profiles\">
        <transport_descriptors>
            <transport_descriptor>
                <transport_id>CustomUDPTransport</transport_id>
                <type>UDPv4</type>
                <interfaceWhiteList>
                    <address>${ipinet##inet }</address>
                </interfaceWhiteList>
            </transport_descriptor>

            <transport_descriptor>
                <transport_id>CustomTcpTransport</transport_id>
                <type>TCPv4</type>
                <interfaceWhiteList>
                    <address>${ipinet##inet }</address>
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

        <participant profile_name=\"CustomTcpTransportParticipant\">
            <rtps>
                <userTransports>
                    <transport_id>CustomTcpTransport</transport_id>
                </userTransports>
            </rtps>
        </participant>
    </profiles>" > /tmp/fastrtps_interface_restriction.xml
    # tell where to look
    export FASTRTPS_DEFAULT_PROFILES_FILE=/tmp/fastrtps_interface_restriction.xml

    # Cyclone DDS https://dds-demonstrators.readthedocs.io/en/latest/Teams/1.Hurricane/setupCycloneDDS.html
    if [[ -n $legacy_cyclonedds ]]; then
        export CYCLONEDDS_URI="<General><NetworkInterfaceAddress>$interface"
    else
        export CYCLONEDDS_URI='<General><Interfaces><NetworkInterface name="$interface"/>'
    fi                

    # we probably do not want to limit to localhost
    unset ROS_LOCALHOST_ONLY

    # only update history and prompt if raw call
    if [[ $# -eq 1 ]]; then
        ros_management_add ros_restrict $interface
        ros_management_prompt $interface 15
    fi
}

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







# special functions for network setup on Centrale Nantes's robots
# show several usages of ros_restrict

ros_reset()
{
    # reset to standard network settings
    unset ROS_IP
    unset ROS_MASTER_URI

    # ROS_LOCALHOST_ONLY with cyclonedds URI
    ros_restrict lo --nohistory

    ros_management_prompt __CLEAN
    ros_management_add ros_reset
}

ros_baxter()
{
    # ROS 1 uses Baxter's ROSMASTER through ethernet
    local ethernet_interface=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}')
    local ethernet_interface=$(for dev in $ethernet_interface; do [ ! -e /sys/class/net/"$dev"/wireless ] && echo ${dev##*/}; done)
    export ROS_IP=$(ip addr show $ethernet_interface | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    export ROS_MASTER_URI=http://baxter.local:11311

    # force ROS 2 on localhost, Baxter runs on ROS 1 anyway
    ros_restrict lo --nohistory

    # prompt and store
    ros_management_prompt baxter 124
    ros_management_add ros_baxter
}

ros_turtle()
{
    if [[ $# -eq 0 ]]; then
        echo "Give a turtlebot number to setup ROS 2 connection"
        return
    fi

    # Domain ID depends on turtlebot
    export ROS_DOMAIN_ID=$1

    # force ROS 2 on wifi, do not save it in history
    ros_restrict WIFI --nohistory

    # prompt and store
    ros_management_prompt turtlebot$1 $((111+$1))
    ros_management_add ros_turtle $1
}

# deal with auto init
if [[ $ROS_MANAGEMENT_ARGS == *"-k"* ]] && [[ -e ~/.ros_management_auto_init ]]; then
    # requested + file here
    source ~/.ros_management_auto_init
else

    # check imposed ROS version
    if [[ $ROS_MANAGEMENT_ARGS =~ (.*)(-ros)([12])(.*) ]]; then
        eval "ros${BASH_REMATCH[3]}ws"
    fi
    
    # check localhost only
    if [[ $ROS_MANAGEMENT_ARGS == *"-lo"* ]]; then
        ros_restrict lo
    fi
fi
