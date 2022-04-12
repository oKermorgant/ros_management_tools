#!/bin/bash

# Switch between ROS 1 / ROS 2 workspaces without messing with environment variables
# Olivier Kermorgant

# ROS 1 / 2 workspaces are defined in overlay ordering 
# ex: ros1_workspaces="/opt/ros/noetic $HOME/ros_ws1 $HOME/ros_ws2"

# replace tilde by home dir in paths
export ros1_workspaces="${ros1_workspaces//'~'/$HOME}"
export ros2_workspaces="${ros2_workspaces//'~'/$HOME}"
export PS1_ori=$PS1

ROS_MANAGEMENT_INIT_FILE=~/.ros_management_auto_init

# use auto-initialization from file if sourced with -k
if [[ "$*" == *"-k"* ]]; then
    ROS_MANAGEMENT_AUTO_INIT=1
else
    unset ROS_MANAGEMENT_AUTO_INIT
    rm -rf $ROS_MANAGEMENT_INIT_FILE
fi

# modify prompt if sourced with -p
if [[ "$*" == *"-p"* ]]; then
    ROS_MANAGEMENT_PROMPT=1
else
    unset ROS_MANAGEMENT_PROMPT
fi

# add a command for the next auto-init
ros_management_add()
{
    if [[ -z $ROS_MANAGEMENT_AUTO_INIT ]]; then
        return
    fi

    if [[ ! -e $ROS_MANAGEMENT_INIT_FILE ]]; then
        echo "$*" > $ROS_MANAGEMENT_INIT_FILE
        return
    fi
    
    local ros_history=$(<$ROS_MANAGEMENT_INIT_FILE)
 
    # only valid commands are ros1ws vs ros2ws and any ros_ (exclusive)    
    if [[ "$*" == *"ws" ]]; then
        local updated=${ros_history/ros[12]ws/$*}
    else
        local updated=$(echo "$ros_history" | sed "s/ros_.*/$*/")
    fi
        
    if [[ $updated != $ros_history ]]; then
        echo "$updated" > $ROS_MANAGEMENT_INIT_FILE
    else
        if [[ "$updated" != *"$*"* ]]; then
            echo "$*" >> $ROS_MANAGEMENT_INIT_FILE
        fi
    fi
}

# add ROS info to the prompt in order to know what version we use
# also indicates on which robot we are working, if any
ros_management_prompt()
{
    if [[ -z $ROS_MANAGEMENT_PROMPT ]] || [[ -z $ROS_DISTRO ]]; then
        return
    fi
    
    local token_color="\[\e[39m\]"
    if [[ $ROS_DISTRO == "noetic" ]]; then
        # actually we always disable the special prompt for ROS 1        
        local DUMMY_LINE=1
        #local ROS_COLOR="\[\e[38;5;17m\]"  # noetic green
        #local ROS_PROMPT="${ROS_COLOR}[ROS1" 
    else        
        local ROS_COLOR=$(
        case "$ROS_DISTRO" in
            ("foxy") echo "166" ;;
            ("galactic") echo "87" ;;
            ("rolling") echo "40" ;;
#             ("humble") echo "86" ;;        
            (*) echo "255" ;;
        esac)
        local ROS_COLOR="\[\e[38;5;${ROS_COLOR}m\]"
        local ROS_PROMPT="${ROS_COLOR}[ROS2"
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
            # token only (ROS 1 not displayed)
            if [[ $cur_prompt != "ROS2"* ]]; then
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
ros_management_prompt
ros_management_add ros1ws
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
ros_management_prompt
ros_management_add ros2ws
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

# restrict fastrtps / Cyclone DDS to this network interface
ros_restrict()
{
    if [[ $# -eq 0 ]]; then
        echo "ros_restrict: give a network interface"
        return
    fi

    # Fast-DDS https://fast-dds.docs.eprosima.com/en/latest/fastdds/transport/whitelist.html
    # needs actual ip for this interface
    ipinet="$(ip a s $1 | egrep -o 'inet [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')"
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

    # Cyclone DDS https://dds-demonstrators.readthedocs.io/en/latest/Teams/1.Hurricane/setupCycloneDDS.html
    echo " <?xml version=\"1.0\" encoding=\"UTF-8\" ?>
    <CycloneDDS xmlns=\"https://cdds.io/config\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:schemaLocation=\"https://cdds.io/config https://raw.githubusercontent.com/eclipse-cyclonedds/cyclonedds/master/etc/cyclonedds.xsd\">
        <Domain id=\"any\">
            <General>
                <NetworkInterfaceAddress>$1</NetworkInterfaceAddress>
            </General>
        </Domain>
    </CycloneDDS>" > /tmp/cyclonedds_interface_restriction.xml

    # tell where to look
    export FASTRTPS_DEFAULT_PROFILES_FILE=/tmp/fastrtps_interface_restriction.xml
    export CYCLONEDDS_URI=file:///tmp/cyclonedds_interface_restriction.xml

    # we probably do not want to limit to localhost
    unset ROS_LOCALHOST_ONLY

    # only update history if raw call
    if [[ $# -eq 1 ]]; then
        ros_management_add ros_restrict $1
    fi
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



# special functions for network setup on Centrale Nantes's robots

ros_reset()
{
    # reset to standard network settings
    unset ROS_IP
    unset ROS_MASTER_URI
    export ROS_LOCALHOST_ONLY=1
    
    unset ROS_DOMAIN_ID
    unset FASTRTPS_DEFAULT_PROFILES_FILE
    unset CYCLONEDDS_URI
    
    ros_management_prompt __CLEAN
    ros_management_add ros_reset
}

ros_baxter()
{
    # ROS 1 uses Baxter's ROSMASTER through ethernet
    ethernet_interface=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}')
    export ROS_IP=$(ip addr show $ethernet_interface | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    export ROS_MASTER_URI=http://baxter.local:11311

    # force ROS 2 on localhost, Baxter runs on ROS 1 anyway
    export ROS_LOCALHOST_ONLY=1
    unset FASTRTPS_DEFAULT_PROFILES_FILE
    unset CYCLONEDDS_URI
    
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

    # force ROS 2 on wifi
    wifi_interface=$(for dev in /sys/class/net/*; do [ -e "$dev"/wireless ] && echo ${dev##*/}; done)
    ros_restrict $wifi_interface --nohistory
    
    # prompt and store
    ros_management_prompt turtlebot$1 113
    ros_management_add ros_turtle $1
}

# deal with history
ros_management_init()
{
    # check if we are imposed a ROS version when sourcing this script            
    if [[ "$*" =~ (.*)(-ros)([12])(.*) ]]; then
        ROS_MANAGEMENT_VERSION="${BASH_REMATCH[3]}"
        # source if no history
        if [[ -z $ROS_MANAGEMENT_AUTO_INIT ]] || [[ ! -e $ROS_MANAGEMENT_INIT_FILE ]] || [[ -z $(grep '^ros[12]ws' $ROS_MANAGEMENT_INIT_FILE) ]]; then    
            eval "ros${ROS_MANAGEMENT_VERSION}ws"
        fi
    fi

    # eval history if requested
    if [[ ! -z $ROS_MANAGEMENT_AUTO_INIT ]] && [[ -e $ROS_MANAGEMENT_INIT_FILE ]]; then
        source $ROS_MANAGEMENT_INIT_FILE
    fi
}

ros_management_init "'$*'"
