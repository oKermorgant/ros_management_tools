#!/bin/bash

# aliases used at Centrale Nantes for high-level config during labs
# show several usages of ros_restrict


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
    __rmt_prompt baxter 124
    __rmt_add ros_baxter
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
    __rmt_prompt franka 37
    __rmt_add ros_franka
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
    __rmt_prompt turtlebot$1 $((111+$1))
    __rmt_add ros_turtle $1 $2
}
