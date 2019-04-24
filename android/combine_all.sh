#!/usr/bin/env bash

set -euo pipefail

# Combine build artifact objects into one library.
#
# The Microsoft Windows tools use different file extensions than the other tools:
# '.obj' as the object file extension, instead of '.o'
# '.lib' as the static library file extension, instead of '.a'
# '.dll' as the shared library file extension, instead of '.so'
#
# The Microsoft Windows tools have different names than the other tools:
# 'lib' as the librarian, instead of 'ar'. 'lib' must be found through the path
# variable $VS140COMNTOOLS.
#
# $1: The platform
# $2: The list of object file paths to be combined
# $3: The output library name
function combine::objects() {
    local platform="$1"
    local outputdir="$2"
    local libname="libwebrtc_full"

    # if [ $platform = 'win' ]; then
    #   local extname='obj'
    # else
    #   local extname='o'
    # fi

    pushd $outputdir >/dev/null
        rm -f $libname.*

        # Prevent blacklisted objects such as ones containing a main function from
        # being combined.
        # Blacklist objects from video_capture_external and device_info_external so
        # that the internal video capture module implementations get linked.
        # unittest_main because it has a main function defined.
        local blacklist="unittest|examples|tools|yasm/|protobuf_lite|main.o|video_capture_external.o|device_info_external.o"

        # Method 1: Collect all .o files from .ninja_deps and some missing intrinsics
        local objlist=$(strings .ninja_deps | grep -o ".*\.o")
        local extras=$(find \
            obj/third_party/libvpx/libvpx_* \
            obj/third_party/libjpeg_turbo/simd_asm \
            obj/third_party/boringssl/boringssl_asm -name "*\.o")
        echo "$objlist" | tr ' ' '\n' | grep -v -E $blacklist >$libname.list
        echo "$extras" | tr ' ' '\n' | grep -v -E $blacklist >>$libname.list

        # Method 2: Collect all .o files from output directory
        # local objlist=$(find . -name '*.o' | grep -v -E $blacklist)
        # echo "$objlist" >$libname.list

        # Combine all objects into one static library
        case $platform in
        win)
            # TODO: Support VS 2017
            "$VS140COMNTOOLS../../VC/bin/lib" /OUT:$libname.lib @$libname.list
            ;;
        *)
            # Combine *.o objects using ar
            cat $libname.list | xargs ar -crs $libname.a

            # Combine *.o objects into a thin library using ar
            # cat $libname.list | xargs ar -ccT $libname.a

            ranlib $libname.a
            ;;
        esac
    popd >/dev/null
}

# Combine built static libraries into one library.
#
# NOTE: This method is currently preferred since combining .o objects is
# causing undefined references to libvpx intrinsics on both Linux and Windows.
#
# The Microsoft Windows tools use different file extensions than the other tools:
# '.obj' as the object file extension, instead of '.o'
# '.lib' as the static library file extension, instead of '.a'
# '.dll' as the shared library file extension, instead of '.so'
#
# The Microsoft Windows tools have different names than the other tools:
# 'lib' as the librarian, instead of 'ar'. 'lib' must be found through the path
# variable $VS140COMNTOOLS.
#
# $1: The platform
# $2: The list of object file paths to be combined
# $3: The output library name
function combine::static() {
    local platform="$1"
    local target_os="$2"
    local outputdir="$3"
    local libname="$4"

    echo $libname
    pushd $outputdir >/dev/null
        rm -f $libname.*

        # Find only the libraries we need
        if [ $platform = 'win' ]; then
            local whitelist="boringssl.dll.lib|protobuf_lite.dll.lib|webrtc\.lib|field_trial_default.lib|metrics_default.lib"
        else
            local whitelist="boringssl\.a|protobuf_full\.a|webrtc\.a|field_trial_default\.a|metrics_default\.a"
        fi
        cat .ninja_log | tr '\t' '\n' | grep -E $whitelist | sort -u >$libname.list

        # Combine all objects into one static library
        case $platform in
        win)
            # TODO: Support VS 2017
            "$VS140COMNTOOLS../../VC/bin/lib" /OUT:$libname.lib @$libname.list
            ;;
        mac)
            if [[ $target_os == "mac" ]] || [[ $target_os == "ios" ]]
            then
                # Combine *.a static libraries
                libtool -static -o $libname.a $(cat $libname.list)
            else
                # Combine *.a static libraries
                echo "CREATE $libname.a" >$libname.ar
                while read a; do
                    echo "ADDLIB $a" >>$libname.ar
                done <$libname.list
                echo "SAVE" >>$libname.ar
                echo "END" >>$libname.ar
                cat $libname.ar
                echo "ar -M < $libname.ar"
                ar -M < $libname.ar
                ranlib $libname.a
            fi
            ;;
        *)
            # Combine *.a static libraries
            echo "CREATE $libname.a" >$libname.ar
            while read a; do
                echo "ADDLIB $a" >>$libname.ar
            done <$libname.list
            echo "SAVE" >>$libname.ar
            echo "END" >>$libname.ar
            ar -M < $libname.ar
            ranlib $libname.a
            ;;
        esac
    popd >/dev/null
}

function combineAllAndroid()
{
    platform=$1
    target_os=$2
    out=$3
    target_cpus="$4"
    configs="$5"

    for cfg in $(echo $configs)
    do
        for target_cpu in $(echo $target_cpus)
        do  
            echo "Processing: combine::static: $platform $target_os \"$out/$target_cpu/$cfg\" libwebrtc_full"
            combine::static $platform $target_os "$out/$target_cpu/$cfg" libwebrtc_full
        done
    done
}

combineAllAndroid linux android out/android/src/out "arm arm64 x86 x64" "Debug Release" 
