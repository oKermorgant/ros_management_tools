#!/bin/bash

# Switch between ROS 1 / ROS 2 workspaces without messing with environment variables
# Helpers for colcon (colbuild) and network interfaces with ROS 2
# Olivier Kermorgant

# ROS 1 / 2 workspaces are defined in overlay ordering
# ex: ros1_workspaces="/opt/ros/noetic $HOME/ros_underlay $HOME/ros_overlay"

# replace tilde by home dir in paths
export ros1_workspaces="${ros1_workspaces//'~'/$HOME}"
export ros2_workspaces="${ros2_workspaces//'~'/$HOME}"
export PS1_ori=$PS1

# store arguments to this script to be used in inner functions
ROS_MANAGEMENT_ARGS="$*"


# add a command for the next auto-init
__ros_management_add()
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
__ros_management_prompt()
{
    if [[ $ROS_MANAGEMENT_ARGS != *"-p"* ]] || [[ -z $ROS_DISTRO ]]; then
        return
    fi

    local token_color="\[\e[39m\]"

    # get sourced version, if any
    local default_ros="0"
    if [[ $ROS_MANAGEMENT_ARGS =~ (.*)(-ros)([12])(.*) ]]; then
        local default_ros="${BASH_REMATCH[3]}"
    fi

    # we disable the prompt for the version that was given in source (assumed to be the default/quiet version)
    if [[ $ROS_VERSION == "1" ]] || [[ $ROS_DISTRO == "noetic" ]] || [[ $ROS_DISTRO == "<unknown>" ]] || [[ $ROS_DISTRO == "Debian" ]] || [[ $ROS_DISTRO == "obese" ]]; then
        if [[ $default_ros != "1" ]]; then
            local ROS_COLOR="\[\e[38;5;106m\]"  # noetic green
            local ROS_PROMPT="${ROS_COLOR}[ROS1"
        fi
    else
        if [[ $default_ros != "2" ]]; then
            local ROS_COLOR=$(
            case "$ROS_DISTRO" in
                ("foxy") echo "166" ;;
                ("galactic") echo "87" ;;
                ("rolling") echo "40" ;;
                ("humble") echo "74" ;;
                ("jazzy") echo "90" ;;
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
__ros_management_remove_paths()
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

# Register a single ROS 1 / 2 workspace, try to source in order : ws > ws/install > ws/devel (ROS 1)
__ros_management_register_workspace()
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

# Equivalent of roscd but jumps to the source, assuming a symlink install
ros2cd()
{
    local dest=$(ros2 pkg prefix $1 --share)
    if [[ $dest == *"not found" ]]; then
        echo "Could not find package $1"
        return
    fi

    # Try to make it to the source if symlink
    local abs_pkg=$(readlink ${dest}/package.xml)
    if [[ $abs_pkg != "" ]]; then
        local dest=$(dirname $abs_pkg)
    fi
    cd $dest
}

# Activate ROS 1 ws
ros1ws()
{
    # check if manual sourcing is mixed with this tool
    local manual_source=$(sed -r '/^(\s*#|$)/d;' ~/.bashrc | grep -E "source.*setup.*sh" | sed -e 's/source //g')
    if [ ! -z "$manual_source" ]; then
        echo "You mix ros_management_tools and manual sourcing in .bashrc, this may have undefined behavior"
        echo "   - ros1_workspaces: $ros1_workspaces"
        for ws in $manual_source
        do
            echo "   - manual sourcing: $ws"
        done
    fi

    export ROS_VERSION=1
    export ROS_DISTRO="<unknown>"
    # Clean ROS 2 paths
    export PYTHONPATH=$(__ros_management_remove_paths "$PYTHONPATH" $ros2_workspaces)
    export CMAKE_PREFIX_PATH=$(__ros_management_remove_paths "$CMAKE_PREFIX_PATH" $ros2_workspaces)
    export PATH=$(__ros_management_remove_paths "$PATH" $ros2_workspaces)
    export LD_LIBRARY_PATH=$(__ros_management_remove_paths "$LD_LIBRARY_PATH" $ros2_workspaces)
    unset ROS_DISTRO

    # register ROS 1 workspaces
    local ws
    for ws in $ros1_workspaces
    do
        __ros_management_register_workspace $ws
    done
    for ws in $ros1_workspaces
    do
        __ros_management_register_workspace $ws
    done

    if [ -f /usr/share/gazebo/setup.sh ]; then
        source /usr/share/gazebo/setup.sh
    fi

    # change prompt if you like (actually not by default)
    if [[ $# -eq 0 ]]; then
        __ros_management_prompt
        __ros_management_add ros1ws
    fi
}

# Activate ROS 2 ws
ros2ws()
{
    # check if manual sourcing is mixed with this tool
    local manual_source=$(sed -r '/^(\s*#|$)/d;' ~/.bashrc | grep -E "source.*setup.*sh" | sed -e 's/source //g')
    if [ ! -z "$manual_source" ]; then
        echo "You mix ros_management_tools and manual sourcing in .bashrc, colbuild will have undefined behavior"
        echo "   - ros2_workspaces: $ros2_workspaces"
        for ws in $manual_source
        do
            echo "   - manual sourcing: $ws"
        done
    fi

    # Clean ROS 1 paths
    export PYTHONPATH=$(__ros_management_remove_paths "$PYTHONPATH" $ros1_workspaces)
    export CMAKE_PREFIX_PATH=$(__ros_management_remove_paths "$CMAKE_PREFIX_PATH" $ros1_workspaces)
    export PATH=$(__ros_management_remove_paths "$PATH" $ros1_workspaces)
    export LD_LIBRARY_PATH=$(__ros_management_remove_paths "$LD_LIBRARY_PATH" $ros1_workspaces)
    unset ROS_DISTRO

    # register ROS 2 workspaces
    local ws
    for ws in $ros2_workspaces
    do
        __ros_management_register_workspace $ws
    done

    # add base ROS 1 libs in case some ROS 2 pkg need them
    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/ros/noetic/lib


    if [ -f /usr/share/gazebo/setup.sh ]; then
        source /usr/share/gazebo/setup.sh
    fi


    # update ROS prompt
    if [[ $# -eq 0 ]]; then
        __ros_management_prompt
        __ros_management_add ros2ws
    fi
}

# colcon build shortcut
colbuild()
{
    # Clean ROS 1 paths
    export PYTHONPATH=$(__ros_management_remove_paths "$PYTHONPATH" $ros1_workspaces)
    export CMAKE_PREFIX_PATH=$(__ros_management_remove_paths "$CMAKE_PREFIX_PATH" $ros1_workspaces)
    export PATH=$(__ros_management_remove_paths "$PATH" $ros1_workspaces)
    export LD_LIBRARY_PATH=$(__ros_management_remove_paths "$LD_LIBRARY_PATH" $ros1_workspaces)
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
            # add all args, change -p to --packages-select and -pu to --packages-up-to
            # also add -t / --this to compile the package we are in
            for arg in $@; do
                case "$arg" in
                    ("-p") cmd="$cmd --packages-select" ;;
                    ("-pu") cmd="$cmd --packages-up-to" ;;
                    ("-t");&
                    ("--this")
                    # identify this package
                    local this_dir=$PWD
                    while [[ ! -e "$this_dir/package.xml" ]]
                    do
                        if [[ "$ws" = "$this_dir/"* ]]; then
                            # we went up to the workspace root: could not identify package
                            break
                        fi
                        this_dir=$(dirname $this_dir)
                    done
                    if [[ -e "$this_dir/package.xml" ]]; then
                        local pkg=$(grep -oP '(?<=<name>).*?(?=</name>)' $this_dir/package.xml)
                        cmd="$cmd --packages-select $pkg"
                    fi
                    ;;
                    ("-tu");&
                    ("--this-up-to")
                    # identify this package
                    local this_dir=$PWD
                    while [[ ! -e "$this_dir/package.xml" ]]
                    do
                        if [[ "$ws" = "$this_dir/"* ]]; then
                            # we went up to the workspace root: could not identify package
                            break
                        fi
                        this_dir=$(dirname $this_dir)
                    done
                    if [[ -e "$this_dir/package.xml" ]]; then
                        local pkg=$(grep -oP '(?<=<name>).*?(?=</name>)' $this_dir/package.xml)
                        cmd="$cmd --packages-up-to $pkg"
                    fi
                    ;;
                    (*) cmd="$cmd $arg" ;;
                esac
            done

            if [ -d "$ws/src/ros1_bridge" ]; then
                cmd="$cmd  --packages-skip ros1_bridge"
            fi
            (cd $ws;eval $cmd)
        fi
        # source anyway
        __ros_management_register_workspace $ws
    done
}

# colcon clean
colclean()
{
    local PWD="$(pwd)/"
    # no args = clean this package
    if [[ $# -eq 0 ]]; then        
        for ws in $ros2_workspaces; do
            if [[ "$PWD" = "$ws/"* ]]; then
                local this_dir=$PWD
                while [[ ! -e "$this_dir/package.xml" ]]
                do
                    if [[ "$ws" = "$this_dir/"* ]]; then
                        # we went up to the workspace root: could not identify package
                        break
                    fi
                    this_dir=$(dirname $this_dir)
                done
                if [[ -e "$this_dir/package.xml" ]]; then                    
                    local pkg=$(grep -oP '(?<=<name>).*?(?=</name>)' $this_dir/package.xml)
                    local cmd="rm -rf build/$pkg install/$pkg log/$pkg"
                    local ws_root=$ws
                    break
                fi
            fi
        done
    else
        local pkgs="$*"
        local ws_root=""
        for ws_root in $ros2_workspaces; do
            # if in this workspace, delete corresponding folders
            if [[ "$PWD" = "$ws_root/"* ]]; then
                local cmd="rm -rf"
                for pkg in $pkgs; do
                    local cmd="$cmd build/$pkg install/$pkg log/$pkg"
                done
                break
            fi
        done
    fi
    
  if [[ -z $cmd ]]; then
    echo "Not in a ROS 2 workspace or package"
    return
  fi

  echo "[Workspace @ $ws_root]: will run $cmd"
  read -p "Proceed with package clean [Y/n] " -n 1 -r
  echo    # (optional) move to a new line
  # check if reply is null or equal to Y or y
  if [[ -z $REPLY ]] || [[ $REPLY =~ ^[Yy]$ ]]; then
    (cd $ws_root;eval $cmd)
    __ros_management_register_workspace $ws_root
  else
    echo "  operation cancelled"
  fi
}

# restrict FastRTPS / Cyclone DDS to this network interface
ros_restrict()
{
    if [[ $# -eq 0 ]]; then
        echo "ros_restrict: give a network interface or ETH / WIFI / lo (localhost)"
        return
    fi

    # slight change in Cyclone syntax since Humble / 22.04
    if [[ $(lsb_release -sr) < 22.00 ]]; then
        local legacy_cyclonedds=1
    fi

    # auto-detect if basic name
    local interface=$1
    if [[ $1 == "WIFI" ]]; then
        local interface=$(for dev in /sys/class/net/*; do [ -e "$dev"/wireless ] && echo ${dev##*/}; done)
    fi
    if [[ $1 == "ETH" ]]; then
        local interface=$(ip link | awk -F: '$0 !~ "lo|vbox|vir|wl|^[^0-9]"{print $2;getline}')
        local interface=$(for dev in $interface; do [[ ! -e /sys/class/net/"$dev"/wireless && $(grep 1 /sys/class/net/"$dev"/carrier) ]] && echo ${dev##*/}; done)
    fi
    if [[ $1 == "lo" ]]; then
        if [[ $ROS_DISTRO < "iron" ]]; then
            export ROS_LOCALHOST_ONLY=1
        else
            export ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST
        fi
        unset ROS_DISCOVERY_SERVER
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
            __ros_management_add ros_restrict $interface
            __ros_management_prompt __CLEAN
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
    </profiles>" > /tmp/fastrtps_interface_restriction_$USER.xml
    # tell where to look
    export FASTRTPS_DEFAULT_PROFILES_FILE=/tmp/fastrtps_interface_restriction_$USER.xml

    # Cyclone DDS https://dds-demonstrators.readthedocs.io/en/latest/Teams/1.Hurricane/setupCycloneDDS.html
    if [[ -n $legacy_cyclonedds ]]; then
        export CYCLONEDDS_URI="<General><NetworkInterfaceAddress>$interface"
    else
        export CYCLONEDDS_URI="<General><Interfaces><NetworkInterface name=\"${interface}\"/>"
    fi                

    # we probably do not want to limit to localhost
    unset ROS_LOCALHOST_ONLY
    if [[ $ROS_DISTRO > "humble" ]]; then
        export ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET
    fi

    # only update history and prompt if raw call
    if [[ $# -eq 1 ]]; then
        __ros_management_add ros_restrict $interface
        __ros_management_prompt $interface 15
    fi
}

# define Fast-DDS super client when debugging
ros_super_client()
{
    if [[ -z $ROS_DISCOVERY_SERVER ]]; then
        return
    fi

    local server=(${ROS_DISCOVERY_SERVER//:/ })
    echo "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>
 <dds>
     <profiles xmlns=\"http://www.eprosima.com/XMLSchemas/fastRTPS_Profiles\">
         <participant profile_name=\"super_client_profile\" is_default_profile=\"true\">
             <rtps>
                 <builtin>
                     <discovery_config>
                         <discoveryProtocol>SUPER_CLIENT</discoveryProtocol>
                         <discoveryServersList>
                             <RemoteServer prefix=\"44.53.00.5f.45.50.52.4f.53.49.4d.41\">
                                 <metatrafficUnicastLocatorList>
                                     <locator>
                                         <udpv4>
                                             <address>${server[0]}</address>
                                             <port>${server[1]}</port>
                                         </udpv4>
                                     </locator>
                                 </metatrafficUnicastLocatorList>
                             </RemoteServer>
                         </discoveryServersList>
                     </discovery_config>
                 </builtin>
             </rtps>
         </participant>
     </profiles>
 </dds>" > /tmp/fastrtps_interface_restriction_$USER.xml
    # restart ROS 2 daemon with this config
    FASTRTPS_DEFAULT_PROFILES_FILE=/tmp/fastrtps_interface_restriction_$USER.xml ros2restart > /dev/null 2>&1
}


# restart daemon
ros2restart()
{
    ros2 daemon stop
    ros2 daemon start
}

# special functions for network setup on Centrale Nantes's robots
# show several usages of ros_restrict

# configure ROS_IP and ROS_MASTER_URI
# give a network interface and the ROS_MASTER_URI to be used, if not the localhost
ros_master()
{

    if [[ $# -eq 0 ]]; then
        unset ROS_MASTER_URI
        unset ROS_IP
        __ros_management_prompt __CLEAN
        __ros_management_add ros_master
        return
    fi

    export ROS_IP=$(ip addr show $1 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)

    if [[ $# -eq 2 ]]; then
        export ROS_MASTER_URI="http://$2:11311"
    else
        export ROS_MASTER_URI="http://$ROS_IP:11311"
    fi

    __ros_management_prompt $1
    __ros_management_add ros_master $1 $2
}

ros_reset()
{
    # reset to standard network settings
    unset ROS_IP
    unset ROS_MASTER_URI

    # ROS_LOCALHOST_ONLY with cyclonedds URI
    ros_restrict lo --nohistory

    __ros_management_prompt __CLEAN
    __ros_management_add ros_reset
}

ros_baxter()
{
    # ROS 1 uses Baxter's ROSMASTER through ethernet
    # get all network interfaces
    local ethernet_interface=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}')
    # find valid ones on ETH
    local ethernet_interface=$(for dev in $ethernet_interface; do [[ ! -e /sys/class/net/"$dev"/wireless && $(grep 1 /sys/class/net/"$dev"/carrier) ]] && echo ${dev##*/}; done)
    ros_master $ethernet_interface "baxter.local"

    # force ROS 2 on localhost, Baxter runs on ROS 1 anyway
    ros_restrict lo --nohistory

    # prompt and store
    __ros_management_prompt baxter 124
    __ros_management_add ros_baxter
}

ros_franka()
{
    # ROS 1 uses Franka's ROSMASTER through Wifi
    # get all network interfaces
    local wifi_interface=$(for dev in /sys/class/net/*; do [ -e "$dev"/wireless ] && echo ${dev##*/}; done)
    ros_master $wifi_interface "franka.local"

    # force ROS 2 on localhost, Franka runs on ROS 1 anyway
    ros_restrict lo --nohistory

    # prompt and store
    __ros_management_prompt franka 37
    __ros_management_add ros_franka
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

    # on Wifi we better use discovery server, assuming it is on the robot
    # let it as an option - it could replace ROS_DOMAIN_ID
    if [[ $# -ge 2 ]]; then
       local tbot_domain=$1
       local tbot_type=${tbot_domain:0:1}
       local tbot_n=${tbot_domain:1:2}

       if [[ $tbot_type == 2 ]]; then
        local tbot="turtle" # our Turtlebot2's are called turtle#
       else
        local tbot="waffle" # our Turtlebot3's are called waffle#
       fi
       export ROS_DISCOVERY_SERVER="$tbot$tbot_n.local:11811"
    fi

    # prompt and store
    __ros_management_prompt turtlebot$1 $((111+$1))
    __ros_management_add ros_turtle $1 $2
}

# deal with auto init
if [[ $ROS_MANAGEMENT_ARGS == *"-k"* ]] && [[ -e ~/.ros_management_auto_init ]]; then
    # requested + file here
    source ~/.ros_management_auto_init
else

    # no default, source ROS 2
    ros2ws
    
    # check localhost only
    if [[ $ROS_MANAGEMENT_ARGS == *"-lo"* ]]; then
        ros_restrict lo
    fi
fi

# function to pause Gazebo when compiling
gz_compile_watchdog()
{
    local compilers="cmake|c\+\+|colcon|catkin"

    # get gz world control
    local gz_control=$(gz service -l | grep -E "/world/[a-zA-Z0-9_]+/control" -o -m 1)
    local gz_running=1

    while sleep 1 ;
    do
        local compiling=$(ps -A | grep -w -E "$compilers" -c)
        if (( $compiling > 0 && $gz_running > 0 )); then
            echo "Pausing Gz"
            gz service -s $gz_control --reqtype gz.msgs.WorldControl --reptype gz.msgs.Boolean --timeout 3000 --req 'pause: true'  &> /dev/null
            local gz_running=0
        fi
        if (( $compiling == 0 && $gz_running == 0 )); then
            echo "Unpausing Gz"
            gz service -s $gz_control --reqtype gz.msgs.WorldControl --reptype gz.msgs.Boolean --timeout 3000 --req 'pause: false' &> /dev/null
            local gz_running=1
        fi
    done
}

if [[ $ROS_VERSION -eq 2 ]]; then
    complete -W "$(ros2 pkg list)" ros2cd
    complete -W "$(ros2 pkg list)" colclean
fi
