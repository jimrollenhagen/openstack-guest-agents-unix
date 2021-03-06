#!/usr/bin/env bash
##### NOVA AGENT BUILDER
##### how_to:$ sh nova-agent-builder.sh help
##### W.I.P. works fine for most of cases,
#####   needs some updates for RHEL & OpenSuse support

##### Fixing LANG for nodes where it ain't
export LANGUAGE="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export LC_CTYPE="UTF-8"
export LANG="en_US.UTF-8"

##### Var
INSTALL_PIP='easy_install pip'
PIP='pip'

NOVA_AGENT_REPO='git://github.com/rackerlabs/openstack-guest-agents-unix.git'
BASE_DIR="/tmp/test_nova_agent"
REPO_DIR='nova-agent'

PATCHELF_VERSION="0.6"
PATCHELF_TGZ_URL="https://github.com/NixOS/patchelf/archive/${PATCHELF_VERSION}.tar.gz"
PATCHELF_BASE='/tmp/patchelf'
PATCHELF_TGZ_LOCAL="${PATCHELF_BASE}/patchelf-${PATCHELF_VERSION}.tgz"
PATCHELF_SRC_LOCAL="${PATCHELF_BASE}/patchelf-${PATCHELF_VERSION}"

SYSTEM_NOVA_AGENT='/usr/share/nova-agent'
BACKUP_NOVA_AGENT=$SYSTEM_NOVA_AGENT".original"

NOVA_AGENT_BINTAR="$HOME/nova-agent/artifacts"

DISTRO_NAME=`python -c "import platform ; print(platform.dist()[0])"`

# create leading components of DEST except the last, then copy SOURCE to DEST
# required by ./configure for Makefile to use it, doesn't Work in FreeBSD
export INSTALL_D="D"

##### Functions
shout(){
  echo "***************************************************"
  echo $1
  echo "***************************************************"
}

# push CentOS required Xen repo config
centos_xen_repo(){
  cat > /etc/yum.repos.d/CentOS-Xen.repo <<XENEOF
# CentOS-Xen.repo
#
# Please see http://wiki.centos.org/QaWiki/Xen4 for more
# information

[Xen4CentOS]
name=CentOS-\$releasever - xen
baseurl=http://mirror.centos.org/centos/\$releasever/xen4/\$basearch/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6
XENEOF

  yum -y repolist
}

# install patchelf to Git
patchelf_git(){
  shout "installing PatchElf from Git"
  _CURR_DIR=`pwd`
  mkdir -p $PATCHELF_BASE
  cd $PATCHELF_BASE
  wget -c -O "${PATCHELF_TGZ_LOCAL}" "${PATCHELF_TGZ_URL}"
  tar zxvf "${PATCHELF_TGZ_LOCAL}"

  cd $PATCHELF_SRC_LOCAL
  sh bootstrap.sh
  ./configure
  make
  make install
  cd $_CURR_DIR
}

# installing python modules
python_module_installer()
{
  shout "Install required modules"

  if [ `which pip > /dev/null 2>&1 ; echo $?` -ne 0 ]; then
    shout "Installing PIP using: $INSTALL_PIP"
    `$INSTALL_PIP`
  fi

  `$PIP install pycrypto`
  `$PIP install pyxenstore`
  `$PIP install unittest2`
  `$PIP install mox`
}

major_version(){
  export OS_VERSION=`cat $RELEASE_FILE | sed 's/[^0-9.]*//g'`
  export OS_VERSION_MAJOR=`echo $OS_VERSION | awk -F'.' '{print $1}'`
}

# install EPEL repo for CentOS systems
get_epel_repo(){
  shout "enabling EPEL repo"
  major_version
  EPEL_URI='http://epel.mirror.net.in/epel'
  if [ $OS_VERSION_MAJOR -eq 6 ]; then
    EPEL_URI=$EPEL_URI"/6/i386/epel-release-6-8.noarch.rpm"
  elif [ $OS_VERSION_MAJOR -eq 5 ]; then
    EPEL_URI=$EPEL_URI"/5/i386/epel-release-5-4.noarch.rpm"
  else
    shout "This version isn't supported."
    exit_now 1
  fi

  EPEL_RPM='/tmp/epel-6.8.rpm'
  curl -L -o $EPEL_RPM $EPEL_URI
  rpm -ivh $EPEL_RPM && yum repolist
}

# install EL6 XEN repo
get_xen_repo(){
  XEN_URI='http://xenbits.xen.org/people/mayoung/EL6.xen/EL6.xen.repo'
  XEN_RPM='/etc/yum.repos.d/el6.xen.repo'
  curl -L -o $XEN_RPM $XEN_URI
  yum repolist
}

# install pyxenstore from source
install_pyxenstore(){
  cd /tmp
  PYXENSTORE_URL="https://pypi.python.org/packages/source/p/pyxenstore/pyxenstore-0.0.2.tar.gz"
  wget --no-check-certificate $PYXENSTORE_URL
  tar zvxf pyxenstore-0.0.2.tar.gz
  cd pyxenstore-0.0.2
  python setup.py install
  cd -
}

# for distros: RedHat, CentOS, Fedora
install_pre_requisite_redhat(){
  export RELEASE_FILE='/etc/redhat-release'
  cat $RELEASE_FILE

  get_epel_repo

  yum -y install git autoconf gcc gcc-c++ make automake libtool
  yum -y install python-crypto python-devel

  if [ $DISTRO_NAME == "centos" ]; then
    centos_xen_repo
  else
    get_xen_repo
  fi
  yum install -y xen-devel
  patchelf_git

  INSTALL_PIP='yum -y install python-pip'
  PIP='python-pip'
  python_module_installer
}

# for distros: Debian, Ubuntu
install_pre_requisite_debian(){
  export RELEASE_FILE='/etc/debian_version'
  cat $RELEASE_FILE
  apt-get -y update
  apt-get -y install git curl
  apt-get -y install autoconf make automake build-essential python-cjson libxen-dev
  apt-get -y install python-anyjson python-pip python-crypto libtool python-dev
  patchelf_git

  INSTALL_PIP='apt-get install -y python-pip'
  python_module_installer
}

# for distros: Gentoo
install_pre_requisite_gentoo(){
  export RELEASE_FILE='/etc/gentoo-release'
  cat $RELEASE_FILE

  emerge dev-vcs/git autoconf
  emerge patchelf

  INSTALL_PIP='emerge dev-python/pip'
  python_module_installer
}

# for distros: ArchLinux
install_pre_requisite_archlinux(){
  export RELEASE_FILE='/etc/arch-release'
  cat $RELEASE_FILE

  pacman -Sc --noconfirm
  pacman -Sy --noconfirm git autoconf patchelf python-pip

  python_module_installer
}

# for distros: FreeBSD
install_pre_requisite_freebsd(){
    export INSTALL_D=""
    uname -a

    pkg_add -r git autogen automake wget bash libtool
    pkg_add -r py27-unittest2 py27-cryptkit py27-pycrypto py27-mox

    # re-install xen-tool :: required for pyxenstore install
    cd /usr/ports/sysutils/xen-tools
    make reinstall
    cp  /usr/ports/sysutils/xen-tools/work/xen-4.1.3/tools/xenstore/libxenstore.so  /usr/lib
    cp /usr/ports/sysutils/xen-tools/work/xen-4.1.3/tools/xenstore/xs.h /usr/local/include/python2.7/
    cp /usr/ports/sysutils/xen-tools/work/xen-4.1.3/tools/xenstore/xs_lib.h /usr/local/include/python2.7/
    mkdir -p /usr/local/include/python2.7/xen/io
    cp /usr/ports/sysutils/xen-tools/work/xen-4.1.3/xen/include/public/io/xs_wire.h /usr/local/include/python2.7/xen/io/
    cd -

    # installing pyxenstore
    install_pyxenstore

    # patchelf and nova-agent require 'gmake' instead of 'make'
    #  on default shell on FreeBSD `alias make='gmake'` doesn't work
    function make(){
      gmake $@
    }

    patchelf_git
}

# for distros: OpenSuSE
install_pre_requisite_suse(){
  zypper install -y git-core autogen automake libtool
  zypper install -y python-devel xen-devel python-pycrypto python-mox patchelf

  # installing pyxenstore
  install_pyxenstore

  zypper install -y --force-resolution python-unittest2

  # nova-agent require 'gmake' instead of 'make'
  function make(){
    gmake $@
  }
}


install_pre_requisite(){
  if [ -f /etc/redhat-release ]; then
    install_pre_requisite_redhat

  elif [ -f /etc/debian_version ]; then
    install_pre_requisite_debian

  elif [ -f /etc/gentoo-release ]; then
    install_pre_requisite_gentoo

  elif [ -f /etc/arch-release ]; then
    install_pre_requisite_archlinux

  elif [ `uname -s` == 'FreeBSD' ] ; then
    install_pre_requisite_freebsd

  elif [ -f /etc/SuSE-release ] ; then
    install_pre_requisite_suse

  else
    echo 'Un-Managed Distro.'
    exit_now 1

  fi
}

branch_nova_agent(){
  if [ ! -z $NOVA_AGENT_BRANCH ]; then
    git checkout $NOVA_AGENT_BRANCH
  fi
}

patch_nova_agent(){
  PATCH_FILE='/tmp/nova_agent.patch'
  # if create patch from a pull request
  if [ ! -z $NOVA_AGENT_PULL_REQUEST ]; then
    PATCH_URL_BASE='http://github.com/rackerlabs/openstack-guest-agents-unix/pull/'
    export NOVA_AGENT_PATCH_URL="$PATCH_URL_BASE""$NOVA_AGENT_PULL_REQUEST"".patch"
  fi

  # apply patch if env NOVA_AGENT_PULL_REQUEST or NOVA_AGENT_PATCH_URL present
  if [ ! -z $NOVA_AGENT_PATCH_URL]; then
    shout "downloading nova-agent patch from: "$NOVA_AGENT_PATCH_URL
    curl -L -o $PATCH_FILE $NOVA_AGENT_PATCH_URL
    git apply $PATCH_FILE
  fi
}

clone_nova_agent(){
  #Clone Nova agent code from the repo.
  shout "cloning NovaAgent"
  mkdir -p $BASE_DIR
  cd $BASE_DIR

  if [ -d $BASE_DIR/$REPO_DIR ]; then
    cd $REPO_DIR
    git checkout .
    git pull
  else
    git clone $NOVA_AGENT_REPO $REPO_DIR
    cd $REPO_DIR
  fi
  branch_nova_agent
  patch_nova_agent
}

# change sh to bash if FreeBSD
## not usin sed -i or tee ; giving some issues
sh_to_bash_if_bsd(){
  SH_PATH="\/bin\/sh"
  BASH_PATH="\/usr\/local\/bin\/bash"
  if [ `uname -s` == 'FreeBSD' ] ; then
    sed "s/${SH_PATH}/${BASH_PATH}/g" "${1}" > "${1}.bash"
    mv "${1}.bash" "${1}"
    chmod 0755 "${1}"
  fi
}

make_nova_agent(){
  install_pre_requisite

  clone_nova_agent

  sh autogen.sh
  ## placing this as a QuickFix for build-error on FreeBSD
  ## will be fixing it at AutoTools config level once prior tasks are done
  sh_to_bash_if_bsd "./configure"
  ./configure --sbindir=/usr/sbin INSTALL_D="$INSTALL_D"
  sh_to_bash_if_bsd "./lib/Makefile"
  make
}

check_nova_agent(){
  make_nova_agent
  make check
}

collect_bintar(){
  mkdir -p $NOVA_AGENT_BINTAR
  cp $BASE_DIR/$REPO_DIR/nova-agent*.tar.gz $NOVA_AGENT_BINTAR
  shout "Your BINTAR has been copied to $NOVA_AGENT_BINTAR"
  ls $NOVA_AGENT_BINTAR/*
}

bintar_nova_agent(){
  check_nova_agent
  make bintar
  collect_bintar
}

bintar_nova_agent_without_test(){
  make_nova_agent
  make bintar
  collect_bintar
}

##### MAIN

help="$(cat <<'SYNTAX'
++++++++++++++++++++++++++++++++++++++++++++++++++\n
 [HELP] NOVA AGENT Builder\n
++++++++++++++++++++++++++++++++++++++++++++++++++\n
\n
 To just run the test 'make check' for latest pull:\n
   $ sh nova-agent-builder.sh test\n
\n
 To create a bintar for nova-agent with tests run:\n
   $ sh nova-agent-builder.sh bintar\n
\n
 To create a bintar for nova-agent without tests:\n
   $ sh nova-agent-builder.sh bintar_no_test\n
\n
 To apply a Git Patch before running tests/bintar:\n
   provide environment var NOVA_AGENT_PULL_REQUEST\n
   with URL to download the Patch.\n
\n
 To apply Pull Request before running tests/bintar:\n
   provide environment var NOVA_AGENT_PULL_REQUEST\n
   with Pull Request NUMBER to refer.\n
\n
 To perform test/bintar action on another branch:\n
   provide environment var NOVA_AGENT_BRANCH\n
   with Name of the Git Branch to checkout.\n
\n
 ++++++++++++++++++++++++++++++++++++++++++++++++++\n
SYNTAX
)"

function exit_now(){
  # check if '/usr/share/nova-agent' has been backed-up, restore it
  if [ -d $BACKUP_NOVA_AGENT ]; then
    mv $BACKUP_NOVA_AGENT $SYSTEM_NOVA_AGENT
  fi
  exit $1
}

shout "Building nova-agent BINTAR on ${DISTRO_NAME}"

## check if '/usr/share/nova-agent' is present and move it to original.$
if [ -d $SYSTEM_NOVA_AGENT ]; then
  mv $SYSTEM_NOVA_AGENT $BACKUP_NOVA_AGENT
fi

if [ $# -eq 0 ]; then
  shout "Running create Bin tar"
  bintar_nova_agent
elif [ $# -gt 1 ]; then
  shout "Help"
  echo $help
  exit_now 1
elif [ "$1" = "test" ]; then
  shout "Running Checks"
  check_nova_agent
elif [ "$1" = "bintar" ]; then
  shout "Running create Bin tar"
  bintar_nova_agent
elif [ "$1" = "bintar_no_test" ]; then
  shout "Running create Bin tar without tests"
  bintar_nova_agent_without_test
elif [ "$1" = "install_pre_requisite" ]; then
  shout "Just installing pre-requisite... required in certain use-cases."
  install_pre_requisite
else
  echo $help
  exit_now 1
fi

# check if '/usr/share/nova-agent' has been backed-up, restore it
if [ -d $BACKUP_NOVA_AGENT ]; then
  mv $BACKUP_NOVA_AGENT $SYSTEM_NOVA_AGENT
fi
