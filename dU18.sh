#!/bin/bash
#run docker for compile
MYNAME=`whoami`
image_base=ubuntu:18.04
final_image=build:ubuntu18
instant_name=ubuntu18-$MYNAME
inst_hostname=bb_libvirtd
action=$1
VOPTION="-v /tmp/build_package/:/tmp/build_package/"
VOPTION+=" -v /etc/passwd:/etc/passwd:ro -v /etc/shadow:/etc/shadow:ro -v /etc/group:/etc/group:ro"
VOPTION+=" -v$HOME:/home/$MYNAME"
CPATH=$PWD
build_ubuntu18()
{
    hd_ins=`docker image ls $final_image -q`
    if [ "$hd_ins" != "" ];then
        echo "image $final_image already exit, you can try run or login"
        return
    fi
    hd_ins=`docker image ls $image_base -q`
    if [ "$hd_ins" = "" ];then
        docker pull $image_base
    fi

    hd_ins=`docker ps -f NAME=$instant_name -q`
    if [ "$hd_ins" = "" ];then
        echo "docker run -idt --name $instant_name $VOPTION $image_base"
        docker run -idt --name $instant_name $VOPTION $image_base 
    fi
 
    docker exec -it $instant_name bash -c 'apt-get update;apt-get install -y wget autoconf build-essential autogen libtool shtool texinfo pkg-config gettext python-dev zlib1g-dev ruby cmake libxml2-utils xsltproc flex bison'
    [ $? -ne 0 ] && echo "docker run error" && return
    
    docker stop $instant_name
    docker commit $instant_name $final_image 
    [ $? -ne 0 ] && echo "update error" && return
    echo "now the docker image $final_image  for build"
    echo "delete tmp instance"
    docker rm $instant_name
    #echo "run new instance from $final_image "
    #docker run -idt --name $instant_name $VOPTION $final_image
}
run_ubuntu18()
{
    hd_ins=`docker ps -f NAME=$instant_name -q`
    if [ "$hd_ins" = "" ];then
        hd_ins=`docker ps -a -f NAME=$instant_name -q`
        if [ "$hd_ins" = "" ];then
            echo "docker run -idt --name $inst_hostname $VOPTION $final_image"
            docker run -idt --hostname $inst_hostname --name $instant_name $VOPTION $final_image 
        else
            docker start $instant_name
        fi
    else
        echo "$instant_name already running"
    fi
}
if [ "$action" = "dkbuild" ];then
    build_ubuntu18
elif [ "$action" = "dkrun" ];then
    run_ubuntu18
elif [ "$action" = "dkstop" ];then
    docker stop $instant_name
    docker rm $instant_name
elif [ "$action" = "login" ];then
    if [ "$2" = "root" ];then
        docker exec -it $instant_name bash
    else
        MTNAME=`whoami`
        #echo "lgoin as $MYNAME and cd $CPATH"
        eval "docker exec -it $instant_name /bin/bash -c 'cd $CPATH&&su $MTNAME'"
    fi
elif [ "$action" = "sh" ];then
	shift
	command=$@
	[ "$command" = "" ] && echo "command not found"
	echo "run '$command' in Machine  $inst_hostname"
	eval "docker exec -it $instant_name /bin/bash -c 'cd $CPATH&&su -c \"$command\" $MTNAME'"
else
	echo "$0 dkbuild - build ubuntu 18 docker image that had installed compile package"
        echo "$0 dkrun - start ubuntu 18(hostname is $$inst_hostname) in background."
	echo "$0 dkstop - stop ubuntu 18."
        echo "$0 login [root] - login by current user and cd to currect path"
        echo "$0 sh     - run shell script in docker"
fi
