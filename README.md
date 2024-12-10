# Helper functions to configure ROS 2 in terminals

The script `ros_management.bash` is a set of tools to simplify the command line when tweaking ROS 2 (compiling, networking, discovery, etc.).

It also avoids mixing ROS 1 and ROS 2 workspaces, for people using both.

Compared to classical tutorials, this tool takes care of sourcing the ROS workspaces, as long as they are listed (in overlay order) in the two variables `ros1_workspaces` and `ros2_workspaces`. A classical `.bashrc` is similar to:

```bash
# your future .bashrc
ros1_workspaces="/opt/ros/noetic ~/a_first_ros1_workspace ~/main_ros1_overlay"
ros2_workspaces="/opt/ros/foxy ~/some_ros2_workspace ~/main_ros2_overlay"
source /path/to/ros_management.bash
```

Note that `ros1_workspaces` does not have to be defined at all if you only use ROS 2. Most of the tools in this script are actually for ROS 2.

## Installing

The script can simply be sourced from your `.bashrc`. In order to install it in another folder and update your `.bashrc` (or even the one in `/etc/skel`) you may use the install script.

Run `install.bash -h` to have an overview of the installation options :

- `-d/--dest`: where to copy the folder (default current location)
- `-o/--opt`: options to source the tool (default `-p -k -lo`, see below for the details)
- `-s/--skel`: if the /etc/skel/.bashrc should be updated as well (default False)
- `-y/--yes`: do not ask confirmation

If `skel` is used or if the destination is outside the current user home, it will require sudo privilege.

## Switch between ROS 1 or ROS 2

After sourcing the script, calling `ros1ws` or `ros2ws` will source the corresponding workspaces in this terminal:

```bash
ros2_workspaces="/opt/ros/foxy ~/some_ros2_workspace ~/main_ros2_overlay"

# sourcing ros_management.bash and calling ros2ws is equivalent to:
source /opt/ros/foxy/setup.bash
source ~/some_ros2_workspace/install/setup.bash
source ~/main_ros2_overlay/install/setup.bash
# except it also cleans ROS 1 paths (from ros1_workspaces)
```

## Sourcing arguments

#### Modify the prompt with `-p`

If sourced with `-p`, the script will update the bash prompt in order to know:

- whether ROS 1 is active in this terminal (this avoids messing up)
- whether ROS 2 is restricted to a specific network interface
    
```bash
source /path/to/ros_management.bash -p # default ROS 2 sourcing, prompt is not modified
ros1ws # ros1 is now active and [ROS1] is displayed
```

#### Restrict ROS 2 to localhost with `-lo`

In this case the script will set `ROS_LOCALHOST_ONLY` (or equivalent for Iron+) for ROS 2

#### Store settings with `-k`

If the settings are stored then any new terminal will have the same settings as the previous one, assuming that `ros_management.bash` is sourced in your `.bashrc` file.

The idea is that when working on a given robot, or a given ROS version, the special setting is only done once even if new terminals are open afterwards (it may happen when using ROS).

Manual calls to `rosXws` or `ros_restrict` will override `-lo` arguments in new terminals.

Settings are stored in `~/.ros_management_auto_init`, delete this file to restore the default behavior

```bash
source /path/to/ros_management.bash -k && ros2ws # default to ROS 2 + store settings
ros1ws # ros1 is now active and will be active in new terminals
```
```bash
source /path/to/ros_management.bash -k -p # also activate prompt
ros1ws # ros1 is now active and will be active in new terminals, [ROS1] is displayed as well
```

## ROS 2 functions

Besides the sourcing of ROS 1 / ROS 2 workspace, the main use of the tool is to help configuring ROS 2 in details.

## `colcon` shortcuts (colbuild)

In ROS 1, `catkin build` could be run from anywhere inside the workspace while in ROS 2, `colcon build` has to be called from the root (where directories `src`, `build` and `install` lie). In practice, calling `colcon build` from e.g. your package directory will actually use this folder as the workspace.

The command `colbuild` offers the following behavior:

- calls `colcon build --symlink-install --continue-on-errors`
- can be run from anywhere inside the workspace
- before compiling: cleans the environment variables and sources the workspaces up to the current one
- after compiling: re-sources the workspaces (this is what you would do anyway)

It provides additional keywords:

- `-p`: similar to `--packages-select`
- `-pu`: similar to `--packages-up-to`
- `-t`, `--this`: compiles only the package that includes the current directory
- `-tu`, `--this-up-to`: compiles only up to the package that includes the current directory

### Network: restrict to a network interface

The function `ros_restrict` takes a network interface (or `lo` / `WIFI` / `ETH`) and will only use this interface for ROS 2 (in this terminal).
It will configure FastRTPS and Cyclone DDS. In practice, a few XML is needed to properly handle these cases:

- https://fast-dds.docs.eprosima.com/en/latest/fastdds/transport/whitelist.html
- https://answers.ros.org/question/365051/using-ros2-offline-ros_localhost_only1
- https://answers.ros.org/question/405753/limit-ros-traffic-to-specific-network-interface

```bash
ros_restrict WIFI  # only uses WiFi, let the script find the interface name
# or ros_restrict wlan0 if it is the name of the wifi interface
```
If `ros_management.bash` was sourced with `-k` then this restriction is forwarded to any new terminal.

You can get back to localhost only with `ros_reset`. It will set `ROS_LOCALHOST_ONLY` (or `ROS_AUTOMATIC_DISCOVERY_RANGE` for Iron+) with prefered interface being `lo` for ROS 2

### Network: setup super client for FastDDS discovery

It is usually a good idea to use a [discovery server](https://docs.ros.org/en/humble/Tutorials/Advanced/Discovery-Server/Discovery-Server.html) when using ROS 2 over Wifi. The main issue is that by default, command-line tools are not able to introspect the ROS graph as nodes and topics are not automatically discovered.

Calling `ros_super_client` enables a [super client](https://docs.ros.org/en/humble/Tutorials/Advanced/Discovery-Server/Discovery-Server.html#daemon-s-related-tools) session based on the value of `ROS_DISCOVERY_SERVER`, when graph introspection is required.

### Network: restart daemon

Calling `ros2restart` will restart the ROS 2 daemon in case discovery is not functional. It will also reset any `super client`.


## ROS 1 functions

### Network: use a distant ROSMASTER on a given interface

The function `ros_master` will configure `ROS_IP` / `ROS_MASTER_URI` to the given network interface:

```bash
# configures ROS_MASTER_URI=master_hostname.local and ROS_IP=(ip on eth0)
ros_master eth0 master_hostname.local
```

Call `ros_reset` to unset `ROS_IP` and `ROS_MASTER_URI`.


## Examples

A few functions, that are designed for use at Centrale Nantes, show how to combine the previous tools:

- `ros_baxter`: configure ROS 1 to connect on Baxter's ROSMASTER through ethernet, restrict ROS 2 to localhost
- `ros_turtle #turtle`: configure ROS 2 to use the same ROS_DOMAIN_ID as our Turtlebots and restrict to Wifi. If another argument is given, relies on a discovery server on the Turtlebot.

Any similar function can be defined and used with the custom prompt and stored settings. The function should start with `ros_` and are assumed to be exclusive (only the latest called `ros_` function is stored for future terminals).


## Best practices: the .bashrc file should just source the file

The `rosXws` or network function calls should not be put in the `.bashrc` but used in conjunction with the `-k` setting that forwards any setting to new terminals. This way there is no need to change the `.bashrc` file anymore.

If you have many workspaces that you source or not source depending on the project you work on, the simplest approach is probably to have several  `ros2_workspaces=` lines in the `.bashrc` where you uncomment the one you currently want to use:

```bash
ros2_workspaces="/opt/ros/humble /some/path/to/underwater_sim/workspace"
ros2_workspaces="/opt/ros/humble /some/path/to/another/amazing/set_of_packages"
ros2_workspaces="/opt/ros/humble /some/path/to/this_new_project" # <- the one that is used right now
```
At this point you should be rigourous enough to re-source all terminals to make sure they use the same workspaces.

# Some bonus

## Compiling while Gazebo is running

Gazebo can be quite resource-hungry which leads to longer compilation times when working on a node in parallel. The function `gz_compile_watchdog`, defined in `ros_management.bash`, will pause Gazebo when one of this processes is detected: `cmake, c++, colcon, catkin`.


## IDE configuration

The `ide` folder includes a script to generate ad-hoc configuration files (raw CMake / ROS 1 / ROS 2) for Qt Creator and VS Code. With this, IDE's will just treat ROS packages as classical CMake, assuming `catkin` or `colcon` was called before to create and symlink the relevant files.

