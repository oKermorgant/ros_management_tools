#!/usr/bin/env python3

import sys
import os
from shutil import rmtree
from time import localtime, sleep
from subprocess import check_output, Popen
import argparse

try:
    input = raw_input
except:
    pass

def dict_replace(s, d):
    for key in d:
        s = s.replace(key, d[key])
    return s

def extract(s,left='(',right=')'):
    return s.partition(left)[2].partition(right)[0].strip(' ')

parser = argparse.ArgumentParser(formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.description = 'A script to generate Qt Creator configuration file for CMake projects.'
parser.add_argument('-c', metavar='cmakelist_dir', help='Folder of CMakeLists.txt file',default='.')
parser.add_argument('-b', metavar='build_dir', help='Relative build folder',default='./build')
parser.add_argument('--clean', action='store_true', default=False)
parser.add_argument('--yes', action='store_true', default=False)
parser.add_argument('-r', action='store_true', default=False, help="Runs this script recursively from this folder")
args = parser.parse_args()

if args.r:

    ignore = ['build','install','devel']

    def do_dir(d):

        if 'CMakeLists.txt' in os.listdir(d) and 'CMakeLists.txt.user' in os.listdir(d):
            print('Calling gen_qtcreator in ' + d)
            cmd = 'python3 ' + os.path.abspath(__file__) + ' --clean -c ' + d
            try:
                check_output(cmd.split())
            except:
                pass
            return

        for li in os.listdir(d):
            d_new = d + '/' + li
            if os.path.isdir(d_new) and li not in ignore and li[0] != '.':
                do_dir(d_new)

    do_dir('.')
    sys.exit(0)

if args.clean:
    args.yes = True

home = os.path.expanduser('~') + '/'
envID_file = home + '.config/QtProject/QtCreator.ini'
confID_file = home + '.config/QtProject/qtcreator/profiles.xml'
cmake_dir = os.path.abspath(args.c)
cmake_file = cmake_dir + '/CMakeLists.txt'
cmake_user = cmake_file + '.user'
build_dir = os.path.abspath(cmake_dir + '/' + args.b)


class Version:
    def __init__(self, s):
        self.s = self.split(s)

    def split(self,s):
        s = [int(v) for v in s.split('.')]
        if len(s) != 3:
            s += [0]*(3-len(s))
        return s
    def rep(self):
        return '.'.join(str(v) for v in self.s)

    def __eq__(self,s):
        s = self.split(s)
        return s[0] == self.s[0] and s[1] == self.s[1]

    def __ge__(self, s):
        s = self.split(s)
        for i in range(3):
            if self.s[i] > s[i]:
                return True
            elif self.s[i] < s[i]:
                return False
        return True


# get ID's on this computer and Qt Creator version
def readConfig():
    with open(envID_file) as f:
        envID = f.read().split('Settings\EnvironmentId=@ByteArray(')[1].split(')')[0]
    with open(confID_file) as f:
        data = f.read()
        confID = data.split('<value type="QString" key="PE.Profile.Id">')[1].split('<')[0]
        qtcVersion = Version(data.split('<!-- Written by QtCreator ')[1].split(', ')[0])
    return envID, confID, qtcVersion

qt_proc = None

while True:

    if qt_proc is None and (not os.path.exists(envID_file) or not os.path.exists(confID_file)):
        print('Will run QtCreator once to generate local configuration')
        sleep(3)
        qt_proc = Popen(['qtcreator','&'], shell=False)

    try:
        envID, confID, qtcVersion = readConfig()
        break
    except:
        sleep(1)

if qt_proc is not None:
    try:
        qt_proc.kill()
        qt_proc.communicate()
    except: pass

if not os.path.exists(cmake_file):
    print('Could not find CMakeLists.txt, exiting')
    print('Given location: ' + cmake_file)
    sys.exit(0)

if os.path.exists(cmake_user) and not args.yes:
    ans = 'not good'
    while ans not in ('y','n',''):
        ans = input('CMakeLists.txt.user already exists, should I delete it [Y/n]: ').lower()
    if ans == 'n':
        print('CMakeLists.txt.user already exists, exiting')
        sys.exit(0)

# remove previous configs
for li in os.listdir(cmake_dir):
    if li.startswith('CMakeLists.txt.user'):
        print('Removing ' + cmake_dir + '/' + li)
        os.remove(cmake_dir + '/' + li)

with open(cmake_file) as f:
    cmake = f.read().splitlines()
package = ''
targets = []
build_type = 'Debug'

class RosBuild:
    version = None
    tool = ''
    @staticmethod
    def find_ws_root(pkg_dir):

        # find a 'src' directory in this tree
        # if several, pick the one that also has a 'build' folder

        if '/src' not in pkg_dir:
            print('The package path does not comply with ROS standard (no src folder)')
            return None

        tree = pkg_dir.split('/src')

        ros_dir = tree[0]

        if len(tree) > 2:
            # check it is the correct one
            for path in tree[1:]:
                if os.path.exists(f'{ros_dir}/build'):
                    break
                ros_dir += f'/src{path}'
            else:
                # no build directory, workspace is ambiguous
                print('The package path is ambiguous (several src folders), cannot guess the workspace')
                print('Compile (catkin or colcon) from the workspace then run this script again.')
                return None

        # try to identify build tool
        if os.path.exists(f'{ros_dir}/build/COLCON_IGNORE'):
            RosBuild.tool = 'colcon'
        elif os.path.exists(f'{ros_dir}/.catkin_tools'):
            RosBuild.tool = 'catkin'

        if RosBuild.tool:
            print(f'Configuring for ROS {RosBuild.version} workspace compiled through {RosBuild.tool}')
        else:
            RosBuild.tool = ['catkin','colcon'][RosBuild.version-1]
            print(f'Could not identify build tool, picking {RosBuild.tool} for ROS {RosBuild.version}')
        return ros_dir

    @staticmethod
    def get_dirs(package):
        build_dir = ros_dir + '/build/' + package
        bin_dir = ros_dir + '/devel/.private/' + package + '/lib'
        install_dir = ros_dir + '/install/' + package
        if RosBuild.tool == 'colcon':
            bin_dir = build_dir
        return build_dir, bin_dir, install_dir

print('Loading ' + os.path.abspath(cmake_file) + '\n')

has_lib = False
for line in cmake:
    if 'project(' in line:
        package = extract(line)
    elif 'add_library(' in line:
        start = line.find('add_library')
        if '#' not in line[:start]:
            has_lib = True
    elif 'add_executable(' in line:
        start = line.find('add_executable')
        if '#' not in line[:start]:
            target = extract(line,'(',' ')
            if '$' not in target:
                targets.append(target)
    elif 'CMAKE_BUILD_TYPE' in line:
        build_type = extract(line).split()[-1]
    elif 'catkin_package' in line:
        if not RosBuild.version:
            RosBuild.version = 1
    elif 'ament_package' in line:
        if not RosBuild.version:
            RosBuild.version = 2

if len(targets) == 0 and not has_lib:
    print('  no C++ targets for ' + package)

# check build directory - update if ROS unless manually set
bin_dir = build_dir
install_dir = '/usr/local'

if RosBuild.version and not '-b' in sys.argv:

    ros_dir = RosBuild.find_ws_root(os.path.abspath(cmake_dir))
    if ros_dir is None:
        sys.exit(0)

    build_dir, bin_dir, install_dir = RosBuild.get_dirs(package)

    if not os.path.exists(build_dir):
        print(f'You will have to run "{RosBuild.tool} build" before loading the project in Qt Creator')

elif not os.path.exists(build_dir):
    os.mkdir(build_dir)
elif args.clean:
    rmtree(build_dir)
    os.mkdir(build_dir)

print('  build directory: ' + os.path.abspath(build_dir))
print('  bin directory:   ' + os.path.abspath(bin_dir))


# load configuration template
gen_config_path = os.path.dirname(os.path.abspath(__file__))

template_name = 'CMakeLists.txt.user.template.pre4.8'
if qtcVersion == '4.8':
    template_name = 'CMakeLists.txt.user.template.4.8'
elif qtcVersion == '4.9':
    template_name = 'CMakeLists.txt.user.template.4.9'
elif qtcVersion >= '4.10':
    template_name = 'CMakeLists.txt.user.template'

with open(gen_config_path + '/' + template_name) as f:
    config = f.read()

# header = version / time / envID
ct = localtime()
ct_str = []
for key in ('year', 'mon', 'mday','hour','min','sec'):
    ct_str.append(str(getattr(ct, 'tm_'+key)).zfill(2))
time_str = '{}-{}-{}T{}:{}:{}'.format(*ct_str)

replace_dict = {}
replace_dict['<gen_version/>'] = qtcVersion.rep()
replace_dict['<gen_time/>'] =  '{}-{}-{}T{}:{}:{}'.format(*ct_str)
replace_dict['<gen_envID/>'] = envID
replace_dict['<gen_cmake_dir/>'] = cmake_dir
replace_dict['<gen_cmake_build_type/>'] = build_type
replace_dict['<gen_build_dir/>'] = build_dir
replace_dict['<gen_install_dir/>'] = install_dir
replace_dict['<gen_conf/>'] = confID
replace_dict['<gen_target_count/>'] = str(len(targets))
config = dict_replace(config, replace_dict)

# target blocks
start = config.find('<!-- gen_target_begin -->')
start += config[start:].find('\n') + 1
end  = config.find('<!-- gen_target_end -->')-1

target_block = [config[start:end] for target in targets]

for i,target in enumerate(targets):
    replace_dict = {}
    replace_dict['<gen_target_nb/>'] = str(i)
    replace_dict['<gen_target_exec/>'] = target
    replace_dict['<gen_bin_dir/>'] = bin_dir
    target_block[i] = dict_replace(target_block[i], replace_dict)
    print('  found target:    ' + target)

config = config.replace(config[start:end], '\n'.join(target_block))

config = '\n'.join(line for line in config.splitlines() if line.strip() != '' and '!--' not in line)

with open(cmake_user, 'w') as f:
    f.write(config)

