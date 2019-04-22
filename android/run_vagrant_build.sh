#!/usr/bin/env bash

sudo apt-get -y install\
	git\
	python

if [[ ! -d depot_tools ]]
then
	git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
fi

export PATH=$PATH:`pwd`/depot_tools

pushd /vagrant
sudo mkdir -p build_webrtc
sudo chown vagrant build_webrtc
pushd build_webrtc

export DEFAULT_WEBRTC_URL="https://chromium.googlesource.com/external/webrtc.git"

if [[ ! -d src ]]
then
	gclient config --name=src "$DEFAULT_WEBRTC_URL"
	gclient sync --nohooks --no-history

	./src/build/install-build-deps.sh --unsupported --no-syms --no-arm --no-chromeos-fonts --no-nacl
	gclient runhooks
fi

exec_ninja() {
  echo "Running ninja"
  ninja -C $1 $WEBRTC_TARGET
}

# Gets the webrtc revision
get_webrtc_revision() {
    DIR=`pwd`
    cd "$WEBRTC_ROOT/src"
    REVISION_NUMBER=`git log -1 | grep 'Cr-Commit-Position: refs/heads/master@{#' | egrep -o "[0-9]+}" | tr -d '}'`

    if [ -z "$REVISION_NUMBER" ]
    then
      REVISION_NUMBER=`git describe --tags  | sed 's/\([0-9]*\)-.*/\1/'`
    fi

    if [ -z "$REVISION_NUMBER" ]
    then
      echo "Error grabbing revision number"
      exit 1
    fi

    echo $REVISION_NUMBER
    cd "$DIR"
}

# Arm V7 with Neon
function wrarmv7() {
    wrbase
    export GYP_DEFINES="$GYP_DEFINES OS=android"
    export GYP_GENERATOR_FLAGS="$GYP_GENERATOR_FLAGS output_dir=out_android_armeabi-v7a"
    export GYP_CROSSCOMPILE=1
    echo "ARMv7 with Neon Build"
}

# Arm 64
function wrarmv8() {
    wrbase
    export GYP_DEFINES="$GYP_DEFINES OS=android target_arch=arm64 target_subarch=arm64"
    export GYP_GENERATOR_FLAGS="output_dir=out_android_arm64-v8a"
    export GYP_CROSSCOMPILE=1
    echo "ARMv8 with Neon Build"
}

# x86
function wrX86() {
    wrbase
    export GYP_DEFINES="$GYP_DEFINES OS=android target_arch=ia32"
    export GYP_GENERATOR_FLAGS="output_dir=out_android_x86"
    echo "x86 Build"
}

# x86_64
function wrX86_64() {
    wrbase
    export GYP_DEFINES="$GYP_DEFINES OS=android target_arch=x64"
    export GYP_GENERATOR_FLAGS="output_dir=out_android_x86_64"
    echo "x86_64 Build"
}

# Prepare our build
function wrbase() {
    export GYP_DEFINES="host_os=linux libjingle_java=1 build_with_libjingle=1 build_with_chromium=0 enable_tracing=1 enable_android_opensl=0 use_sysroot=0 include_tests=0"
    if [ "$WEBRTC_DEBUG" != "true" ] ;
    then
        export GYP_DEFINES="$GYP_DEFINES fastbuild=2"
    fi
    export GYP_GENERATORS="ninja"
}

# Setup our defines for the build
prepare_gyp_defines() {
    # Configure environment for Android
    echo Setting up build environment for Android
    source "$WEBRTC_ROOT/src/build/android/envsetup.sh"

    # Check to see if the user wants to set their own gyp defines
    echo Export the base settings of GYP_DEFINES so we can define how we want to build
    if [ -z $USER_GYP_DEFINES ]
    then
        echo "User has not specified any gyp defines so we proceed with default"
        if [ "$WEBRTC_ARCH" = "x86" ] ;
        then
            wrX86
        elif [ "$WEBRTC_ARCH" = "x86_64" ] ;
        then
            wrX86_64
        elif [ "$WEBRTC_ARCH" = "armv7" ] ;
        then
            wrarmv7
        elif [ "$WEBRTC_ARCH" = "armv8" ] ;
        then
            wrarmv8
        fi
    else
        echo "User has specified their own gyp defines"
        export GYP_DEFINES="$USER_GYP_DEFINES"
    fi

    echo "GYP_DEFINES=$GYP_DEFINES"
}

# Builds the apprtc demo
execute_build() {
    WORKING_DIR=`pwd`
    cd "$WEBRTC_ROOT/src"

    if [ "$WEBRTC_ARCH" = "x86" ] ;
    then
        ARCH="x86"
        STRIP="$ANDROID_TOOLCHAINS/x86-4.9/prebuilt/linux-x86_64/bin/i686-linux-android-strip"
    elif [ "$WEBRTC_ARCH" = "x86_64" ] ;
    then
        ARCH="x64"
        STRIP="$ANDROID_TOOLCHAINS/x86_64-4.9/prebuilt/linux-x86_64/bin/x86_64-linux-android-strip"
    elif [ "$WEBRTC_ARCH" = "armv7" ] ;
    then
        ARCH="arm"
        STRIP="$ANDROID_TOOLCHAINS/arm-linux-androideabi-4.9/prebuilt/linux-x86_64/bin/arm-linux-androideabi-strip"
    elif [ "$WEBRTC_ARCH" = "armv8" ] ;
    then
        ARCH="arm64"
        STRIP="$ANDROID_TOOLCHAINS/aarch64-linux-android-4.9/prebuilt/linux-x86_64/bin/aarch64-linux-android-strip"
    fi

    if [ "$WEBRTC_DEBUG" = "true" ] ;
    then
        BUILD_TYPE="Debug"
        DEBUG_ARG='is_debug=true'
    else
        BUILD_TYPE="Release"
        DEBUG_ARG='is_debug=false dcheck_always_on=true'
    fi

    ARCH_OUT="out_android_${ARCH}"

    echo Generate projects using GN
    gn gen "$ARCH_OUT/$BUILD_TYPE" --args="$DEBUG_ARG symbol_level=1 target_os=\"android\" target_cpu=\"${ARCH}\""
    #gclient runhooks

    REVISION_NUM=`get_webrtc_revision`
    echo "Build ${WEBRTC_TARGET} in $BUILD_TYPE (arch: ${WEBRTC_ARCH})"
    exec_ninja "$ARCH_OUT/$BUILD_TYPE"

    # Verify the build actually worked
    if [ $? -eq 0 ]; then
        SOURCE_DIR="$WEBRTC_ROOT/src/$ARCH_OUT/$BUILD_TYPE"
        TARGET_DIR="$BUILD/$BUILD_TYPE"
        create_directory_if_not_found "$TARGET_DIR"

        echo "Copy JAR File"
        create_directory_if_not_found "$TARGET_DIR/libs/"
        create_directory_if_not_found "$TARGET_DIR/jni/"

        if [ "$WEBRTC_ARCH" = "x86" ] ;
        then
            ARCH_JNI="$TARGET_DIR/jni/x86"
        elif [ "$WEBRTC_ARCH" = "x86_64" ] ;
        then
            ARCH_JNI="$TARGET_DIR/jni/x86_64"
        elif [ "$WEBRTC_ARCH" = "armv7" ] ;
        then
            ARCH_JNI="$TARGET_DIR/jni/armeabi-v7a"
        elif [ "$WEBRTC_ARCH" = "armv8" ] ;
        then
            ARCH_JNI="$TARGET_DIR/jni/arm64-v8a"
        fi
        create_directory_if_not_found "$ARCH_JNI"

        # Copy the jars
        cp -p $SOURCE_DIR/lib.java/sdk/android/*_java.jar "$TARGET_DIR/libs/"
        cp -p "$SOURCE_DIR/lib.java/rtc_base/base_java.jar" "$TARGET_DIR/libs/rtc_base_java.jar"
        #Copy required jar file containing package "org.webrtc.voiceengine"
        cp -p "$SOURCE_DIR/lib.java/modules/audio_device/audio_device_java.jar" "$TARGET_DIR/libs/audio_device_java.jar"

        # Strip the build only if its release
        if [ "$WEBRTC_DEBUG" = "true" ] ;
        then
            cp -p "$WEBRTC_ROOT/src/$ARCH_OUT/$BUILD_TYPE/libjingle_peerconnection_so.so" "$ARCH_JNI/libjingle_peerconnection_so.so"
            cp -p "$WEBRTC_ROOT/src/$ARCH_OUT/$BUILD_TYPE/libboringssl.cr.so" "$ARCH_JNI/libboringssl.cr.so"
            cp -p "$WEBRTC_ROOT/src/$ARCH_OUT/$BUILD_TYPE/libbase.cr.so" "$ARCH_JNI/libbase.cr.so"
            cp -p "$WEBRTC_ROOT/src/$ARCH_OUT/$BUILD_TYPE/libc++_shared.so" "$ARCH_JNI/libc++_shared.so"
            cp -p "$WEBRTC_ROOT/src/$ARCH_OUT/$BUILD_TYPE/libprotobuf_lite.cr.so" "$ARCH_JNI/libprotobuf_lite.cr.so"
        else
            "$STRIP" -o "$ARCH_JNI/libjingle_peerconnection_so.so" "$WEBRTC_ROOT/src/$ARCH_OUT/$BUILD_TYPE/libjingle_peerconnection_so.so" -s
        fi

        cd "$TARGET_DIR"
        mkdir -p aidl
        mkdir -p assets
        mkdir -p res

        cd "$WORKING_DIR"
        echo "$BUILD_TYPE build for apprtc complete for revision $REVISION_NUM"
    else

        echo "$BUILD_TYPE build for apprtc failed for revision $REVISION_NUM"
        #exit 1
    fi
}

# Updates webrtc and builds apprtc
build_apprtc() {
    export WEBRTC_ARCH=armv7
    prepare_gyp_defines &&
    execute_build

    export WEBRTC_ARCH=armv8
    prepare_gyp_defines &&
    execute_build

    export WEBRTC_ARCH=x86
    prepare_gyp_defines &&
    execute_build

    export WEBRTC_ARCH=x86_64
    prepare_gyp_defines &&
    execute_build
}

export WEBRTC_ROOT=`pwd`
#export WEBRTC_DEBUG=true
build_apprtc
