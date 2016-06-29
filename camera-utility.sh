#!/bin/bash
# This file is part of the RemoteVideoWatcher package.
# (c) Alexander Lukashevich <aleksandr.dwt@gmail.com>
# For the full copyright and license information, please view the LICENSE file that was distributed with this source code.

MACHINE_ARCH=$(uname -m | cut -c1-3 | tr '[:lower:]' '[:upper:]')
WORK_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR=$WORK_DIR/build

DOCKER_ARM_IMAGE=sdhibit/rpi-raspbian
DOCKER_X86_IMAGE=ubuntu

DOCKERFILE_CORDOVA_PATH=$WORK_DIR/Dockerfile-cordova
DOCKERFILE_SERVER_PATH=$WORK_DIR/Dockerfile-server
BUILD_DOCKERFILE_SERVER_PATH=$BUILD_DIR/Dockerfile-server

CERTIFICATE_KEY_PATH=$BUILD_DIR/server.key
CERTIFICATE_CRT_PATH=$BUILD_DIR/server.crt
MJPG_STREAMER_BIN=$BUILD_DIR/mjpg_streamer

CONFIG_FILE=$WORK_DIR/config.yml

SERVER_JS_FILE_NAME=server.js
SERVER_SH_FILE_NAME=cameras.sh
CLIENT_JS_FILE_NAME=index.js
SERVER_JS_FILE_PATH=$WORK_DIR/server/$SERVER_JS_FILE_NAME
SERVER_SH_FILE_PATH=$WORK_DIR/server/$SERVER_SH_FILE_NAME
CLIENT_JS_FILE_PATH=$WORK_DIR/client/www/js/$CLIENT_JS_FILE_NAME
BUILD_SERVER_JS_FILE_PATH=$BUILD_DIR/$SERVER_JS_FILE_NAME
BUILD_SERVER_SH_FILE_PATH=$BUILD_DIR/$SERVER_SH_FILE_NAME
BUILD_CLIENT_JS_FILE_PATH=$BUILD_DIR/$CLIENT_JS_FILE_NAME

NEW_LINE=$'\n'

###################################
######### Program Entry Point #######
#################################
function main {
    if [ "$MACHINE_ARCH" != "ARM" ] && [ "$MACHINE_ARCH" != "X86" ]; then
        echo "This program can work only at X86 or ARM machine. Abort!"
        exit 1
    fi

    case "$1" in
        "build-server")
            buildCameraServer "$@"
            ;;
        "build-client")
            buildCameraClient
            ;;
        "start-server-daemon")
            startCameraServer
            ;;
        "docker-camera-cordova-fix-files")
            # you mustn't use this command yourself
            fixCordovaSslPlugin
            ;;
        "docker-camera-cordova-build")
            # you mustn't use this command yourself
            buildApkInDockerContainer "$@"
            ;;
        *)
        echo "Wrong command. Available commands are:$NEW_LINE$NEW_LINE \
1) build-server [--regenerate-token-crypt-phrase] [--regenerate-server-cert] [--recompile-mjpgstreamer]$NEW_LINE \
Create a docker image which consists of everything what you need to start using this program.$NEW_LINE \
The image includes the NodeJS server to process clients (from web browsers and from mobile applications)$NEW_LINE \
and Mjpg-streamer utility to capture video from web-cameras and send it to NodeJS server.$NEW_LINE$NEW_LINE \
2) build-client$NEW_LINE \
Create .apk file which you can install to your android devices and \
start using this program in the same way as a web browser.$NEW_LINE$NEW_LINE \
3) start-server-daemon$NEW_LINE \
Run server daemon in background.$NEW_LINE Usually you add this command in \
system-autorun on the server machine after running 'build-server' command at least one time.$NEW_LINE"
        exit 1
        ;;
    esac
}

###########################################
#### Create docker image to use on the server ###
##########################################
function buildCameraServer {
    validateConfigFile
    prepareBuildDirectory

    # regenerate parts if required
    for arg in "$@"
    do
        case "$arg" in
            "--regenerate-token-crypt-phrase")
                generateTokenCryptPhrase
                ;;
            "--regenerate-server-cert")
                generateServerCertificate
                ;;
            "--recompile-mjpgstreamer")
                compileMjpgStreamer
                ;;
        esac
    done

    # generate necessary parts if not found
    if [ "$(egrep -c 'certificate_fingerprint:.*none' $CONFIG_FILE)" -gt 0 ] || [ ! -f $CERTIFICATE_KEY_PATH ] || [ ! -f $CERTIFICATE_CRT_PATH ]; then
        echo 'Server certificate files do not exist or certificate_fingerprint parameter is empty!'
        generateServerCertificate
    fi
    if [ "$(egrep -c 'token_crypt_phrase:.*none' $CONFIG_FILE)" -gt 0 ]; then
        echo 'Token_crypt_phrase parameter is empty!'
        generateTokenCryptPhrase
    fi
    if [ ! -f $MJPG_STREAMER_BIN ]; then
        echo 'Mjpg-streamer binary do not exist!'
        compileMjpgStreamer
    fi

    # create copy of main files
    cp $SERVER_JS_FILE_PATH $BUILD_SERVER_JS_FILE_PATH
    cp $SERVER_SH_FILE_PATH $BUILD_SERVER_SH_FILE_PATH
    cp $CLIENT_JS_FILE_PATH $BUILD_CLIENT_JS_FILE_PATH

    # make changes in main files according to config.yml
    replaceConfigParamsInBuildFiles \
        $BUILD_SERVER_JS_FILE_PATH \
        $BUILD_SERVER_SH_FILE_PATH \
        $BUILD_CLIENT_JS_FILE_PATH

    # create docker image for server
    docker build -t alex_dwt/remote-video-watcher-server -f $BUILD_DOCKERFILE_SERVER_PATH $WORK_DIR

    echo 'Docker image with camera-server successfully created!'
}

#########################################################
## Create android application (.apk file) to install on SmartPhone ##
#######################################################
function buildCameraClient {
    if [ "$MACHINE_ARCH" != "X86" ]; then
        echo "You can build client only on X86 machine. Abort!"
        exit 1
    fi

    validateConfigFile
    prepareBuildDirectory

    # check necessary params in config.yml for client_js
    if [ "$(egrep -c 'certificate_fingerprint:.*none' $CONFIG_FILE)" -gt 0 ]; then
        echo "Certificate_fingerprint parameter is empty! Use 'build-server' command at first please. Abort!"
        exit 1
    fi
    if [ "$(egrep -c 'token_crypt_phrase:.*none' $CONFIG_FILE)" -gt 0 ]; then
        echo "Token_crypt_phrase parameter is empty! Use 'build-server' command at first please. Abort!"
        exit 1
    fi

    # create copy of js file
    cp $CLIENT_JS_FILE_PATH $BUILD_CLIENT_JS_FILE_PATH

    # make changes in js file according to config.yml
    replaceConfigParamsInBuildFiles $BUILD_CLIENT_JS_FILE_PATH

    # create docker image for cordova
    docker build -t alex_dwt/remote-video-watcher-cordova -f $DOCKERFILE_CORDOVA_PATH $WORK_DIR

    if [ $? -ne 0 ]
    then
      echo 'Can not create docker image. Abort!'
      exit 1
    fi

    echo 'Started creating android client...'

    # build .apk in docker container
    docker run --rm -it \
        -v $WORK_DIR:/camera-apk \
        alex_dwt/remote-video-watcher-cordova /bin/bash -c "./camera-utility.sh docker-camera-cordova-build"
}

##################################################
## Launch server daemon to start take and share video ###
################################################
function startCameraServer {
    validateConfigFile
    exportConfigParams

    if [ "$(docker images | egrep -c 'alex_dwt/remote-video-watcher-server')" -eq 0 ]; then
        echo "Can not find docker server image. You should run 'build-server' command at first. Abort!"
        exit 0
    fi

    docker rm -f alex-dwt-remote-video-watcher-server >/dev/null 2>&1

    docker run -d \
        -v /opt:/opt:ro \
        -p 443:443 \
        -p $conf_wss_server_port:${conf_wss_server_port} \
        -v /tmp/alex-dwt-remote-video-watcher-server:/camera/streamer/run \
        $(find /dev/ 2>/dev/null | egrep "/dev/video*|/dev/vchiq" | xargs -I {} printf "--device={}:{} ") \
        --name alex-dwt-remote-video-watcher-server alex_dwt/remote-video-watcher-server >/dev/null 2>&1

    if [ $? -ne 0 ]
    then
      echo 'Can not start camera server daemon.'
    else
      echo 'Camera server daemon successfully started!'
    fi
}




function replaceConfigParamsInBuildFiles {
    exportConfigParams

    local CONFIG_TEXT=$(parseYaml $CONFIG_FILE "conf_")
    local CAMERAS_COUNT=$(echo "$CONFIG_TEXT" | egrep -o conf_cameras_[0-9]+ | sort -u | wc -l)

    for arg in "$@"
    do
        if [ ! -f $arg ]; then
            echo "Build file '$arg' does not exist. Abort!"
            exit 1
        fi
        case "$arg" in
            "$BUILD_SERVER_JS_FILE_PATH")
                sed -i "s/%_enable_static_server_%/$conf_enable_static_server/" $BUILD_SERVER_JS_FILE_PATH
                sed -i "s/%_token_crypt_phrase_%/$conf_token_crypt_phrase/" $BUILD_SERVER_JS_FILE_PATH
                sed -i "s/%_wss_server_port_%/$conf_wss_server_port/" $BUILD_SERVER_JS_FILE_PATH
                ;;

            "$BUILD_SERVER_SH_FILE_PATH")
                local cameras_list=''
            	local i=0
                while [ $i -lt $CAMERAS_COUNT ]; do
                    local name="conf_cameras_${i}_name"
                    local command="conf_cameras_${i}_command"
                    cameras_list="$cameras_list$i) # ${!name}$NEW_LINE PID=\$(${!command} > /dev/null 2>__amp__1 __amp__ echo \$!)$NEW_LINE;;"
                    if [ $i -ne $(($CAMERAS_COUNT-1)) ]; then
                        cameras_list="$cameras_list$NEW_LINE"
                    fi
                    i=$(($i+1))
                done
                awk -i inplace -v TEXT="$cameras_list" '{sub(/#_list_of_cameras/, TEXT);print;}' $BUILD_SERVER_SH_FILE_PATH
                sed -i "s/__amp__/\&/g" $BUILD_SERVER_SH_FILE_PATH
                sed -i "s/%_camera_max_id_%/$(($CAMERAS_COUNT-1))/" $BUILD_SERVER_SH_FILE_PATH
                ;;

            "$BUILD_CLIENT_JS_FILE_PATH")
                sed -i "s/%_default_server_ip_%/$conf_default_server_ip/" $BUILD_CLIENT_JS_FILE_PATH
                sed -i "s/%_external_server_ip_%/$conf_external_server_ip/" $BUILD_CLIENT_JS_FILE_PATH
                sed -i "s/%_certificate_fingerprint_%/$conf_certificate_fingerprint/" $BUILD_CLIENT_JS_FILE_PATH
                sed -i "s/%_token_crypt_phrase_%/$conf_token_crypt_phrase/" $BUILD_CLIENT_JS_FILE_PATH
                sed -i "s/%_wss_server_port_%/$conf_wss_server_port/" $BUILD_CLIENT_JS_FILE_PATH
                local cameras_list=''
            	local i=0
                while [ $i -lt $CAMERAS_COUNT ]; do
                    local name="conf_cameras_${i}_name"
                    local revert_option_val="conf_cameras_${i}_has_revert_option"
                    local revert_option_text=''
                    if [ ${!revert_option_val} -eq 1 ]; then
                        revert_option_text="revert: false"
                    fi
                    cameras_list="$cameras_list{label: '${!name}', el: null, options: { $revert_option_text }}"
                    if [ $i -ne $(($CAMERAS_COUNT-1)) ]; then
                        cameras_list="$cameras_list,$NEW_LINE"
                    fi
                    i=$(($i+1))
                done
                awk -i inplace -v TEXT="$cameras_list" '{sub(/\/\/_list_of_cameras/, TEXT);print;}' $BUILD_CLIENT_JS_FILE_PATH
                ;;
        esac
    done
}

function validateConfigFile {
    if [ ! -f $CONFIG_FILE ]; then
        echo 'Config file config.yml does not exist. Abort!'
        exit 1
    fi
    local CONFIG_TEXT=$(parseYaml $CONFIG_FILE "conf_")
    local CAMERAS_COUNT=$(echo "$CONFIG_TEXT" | egrep -o conf_cameras_[0-9]+ | sort -u | wc -l)
    local CAMERAS_LINES_COUNT=$(echo "$CONFIG_TEXT" | egrep -c conf_cameras_[0-9]+)
    if [ $CAMERAS_COUNT -eq 0 ]; then
        echo 'There are no any cameras defined in config.yml. Abort!'
        exit 1
    fi
    if [[ $(( $CAMERAS_LINES_COUNT / $CAMERAS_COUNT )) -ne 3 ]] || [[ $(( $CAMERAS_LINES_COUNT % 3 )) -ne 0 ]]; then
        echo 'Cameras parameters are wrong. Every camera must have three parameters. Abort!'
        exit 1
    fi
    if [ "$(echo "$CONFIG_TEXT" | egrep -c 'conf_wss_server_port|conf_default_server_ip|conf_external_server_ip|conf_enable_static_server|conf_certificate_fingerprint|conf_token_crypt_phrase')" -ne 6 ]; then
        echo 'There is wrong count of parameters in config.yml. Abort!'
        exit 1
    fi
}

function exportConfigParams {
    eval $(parseYaml $CONFIG_FILE "conf_")
}

function prepareBuildDirectory {
    if [ ! -d "$BUILD_DIR" ]; then
        mkdir $BUILD_DIR
        if [ $? -ne 0 ]
        then
          echo 'Can not create build directory. Abort!'
          exit 1
        fi
    fi

    # clear old files
    if [ -f $BUILD_SERVER_JS_FILE_PATH ]; then
        rm -f $BUILD_SERVER_JS_FILE_PATH
        if [ $? -ne 0 ]
        then
            exit 1
        fi
    fi
    if [ -f $BUILD_SERVER_SH_FILE_PATH ]; then
        rm -f $BUILD_SERVER_SH_FILE_PATH
        if [ $? -ne 0 ]
        then
            exit 1
        fi
    fi
    if [ -f $BUILD_CLIENT_JS_FILE_PATH ]; then
        rm -f $BUILD_CLIENT_JS_FILE_PATH
        if [ $? -ne 0 ]
        then
            exit 1
        fi
    fi
    if [ -f $BUILD_DOCKERFILE_SERVER_PATH ]; then
        rm -f $BUILD_DOCKERFILE_SERVER_PATH
        if [ $? -ne 0 ]
        then
            exit 1
        fi
    fi

    # determine what docker base image use to build server
    cp $DOCKERFILE_SERVER_PATH $BUILD_DOCKERFILE_SERVER_PATH

    local image=$DOCKER_ARM_IMAGE
    if [ "$MACHINE_ARCH" == "X86" ]; then
        image=$DOCKER_X86_IMAGE
    fi
    awk -i inplace -v TEXT="$image" '{sub(/%_base_image_name_%/, TEXT);print;}' $BUILD_DOCKERFILE_SERVER_PATH

    if [ $? -ne 0 ]
    then
        echo 'Can not change docker image base name. Abort!'
        exit 1
    fi
}

function fixCordovaSslPlugin {
    echo "Start fixing cordova-plugin-sslcertificatechecker (to accept self-signed certificates)..."

    local IMPORT_BLOCK="\
        import javax.net.ssl.TrustManager; \
        import javax.net.ssl.X509TrustManager; \
        import java.security.cert.X509Certificate; \
        import javax.net.ssl.SSLContext; \
        import java.security.GeneralSecurityException; \
        import javax.net.ssl.HostnameVerifier; \
        import javax.net.ssl.SSLSession;"
    local VERIFY_FUNCTION="\
        private static HostnameVerifier getMyHostnameVerifier() throws GeneralSecurityException { \
            TrustManager[] trustAllCerts = new TrustManager[] { \
                new X509TrustManager() { \
                    public java.security.cert.X509Certificate[] getAcceptedIssuers() { \
                        return new X509Certificate[0]; \
                    } \
                    public void checkClientTrusted( \
                        java.security.cert.X509Certificate[] certs, String authType) { \
                    } \
                    public void checkServerTrusted( \
                        java.security.cert.X509Certificate[] certs, String authType) { \
                    } \
                } \
            }; \
            SSLContext sc = SSLContext.getInstance(\"SSL\"); \
            sc.init(null, trustAllCerts, new java.security.SecureRandom()); \
            HttpsURLConnection.setDefaultSSLSocketFactory(sc.getSocketFactory()); \
            HostnameVerifier hostnameVerifier = new HostnameVerifier() { \
            @Override \
                public boolean verify(String hostname, SSLSession session) { \
                    return true; \
                } \
            }; \
            return hostnameVerifier; \
        }"
    local FIX_FUNCTION_DECLARATION=", GeneralSecurityException \{"
    local SKIP_ACTION="con.setHostnameVerifier(getMyHostnameVerifier());"

    local PLUGIN_FILE=$(find /camera/platforms/android/ -iname "*sslcertificatechecker.java" 2>/dev/null)
    if [ -z "$PLUGIN_FILE" ]
    then
      echo "File not found. Abort!"
      exit 1
    fi

    egrep -qi "package .*" $PLUGIN_FILE
    if [ $? -ne 0 ]
    then
      echo 'Can not find pattern text to replace. Abort!'
      exit 1
    fi
    sed -r -i "s/(package .*)/\1 $IMPORT_BLOCK/I" $PLUGIN_FILE

    egrep -qi "public.*class.*" $PLUGIN_FILE
    if [ $? -ne 0 ]
    then
      echo 'Can not find pattern text to replace. Abort!'
      exit 1
    fi
    sed -r -i "s/(public.*class.*)/\1 $VERIFY_FUNCTION/I" $PLUGIN_FILE

    egrep -qi "private.*getfingerpr.*throws.*\{" $PLUGIN_FILE
    if [ $? -ne 0 ]
    then
      echo 'Can not find pattern text to replace. Abort!'
      exit 1
    fi
    sed -r -i "s/(private.*getfingerpr.*throws.*)\{/\1 $FIX_FUNCTION_DECLARATION/I" $PLUGIN_FILE

    egrep -qi "setconnecttimeout.*" $PLUGIN_FILE
    if [ $? -ne 0 ]
    then
      echo 'Can not find pattern text to replace. Abort!'
      exit 1
    fi
    sed -r -i "s/(setconnecttimeout.*)/\1 $SKIP_ACTION/I" $PLUGIN_FILE

    echo 'Plugin successfully fixed!'
}

function compileMjpgStreamer {
    echo 'Started compiling mjpg-streamer...'
    local image=$DOCKER_ARM_IMAGE

    if [ "$MACHINE_ARCH" == "X86" ]; then
        image=$DOCKER_X86_IMAGE
    fi

    docker run --rm -it \
        -v /opt:/opt:ro \
        -v $BUILD_DIR:/mjpg-streamer-compiled \
        $image /bin/bash -c "apt-get update && \
        apt-get install -y cmake git libjpeg8-dev build-essential && \
        git clone https://github.com/jacksonliam/mjpg-streamer.git && \
        cd /mjpg-streamer/mjpg-streamer-experimental && \
        make && \
        chmod 666 *.so mjpg_streamer && \
        cp *.so mjpg_streamer /mjpg-streamer-compiled/"

    if [ $? -ne 0 ]
    then
      echo 'Can not compile mjpg-streamer. Abort!'
      exit 1
    fi

    echo 'Mjpg-streamer successfully compiled!'
}

function generateTokenCryptPhrase {
    echo 'Started generating token_crypt_phrase...'
    sed -r -i "s/(token_crypt_phrase:).*/\1 $(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-32};echo;)/" $CONFIG_FILE
    echo 'Token_crypt_phrase successfully generated!'
}

function generateServerCertificate {
    echo 'Started generating server certificate...'
    openssl req -x509 -sha256 -nodes -days 1000 -newkey rsa:2048 \
        -keyout $CERTIFICATE_KEY_PATH -out $CERTIFICATE_CRT_PATH \
        -subj "/C=GB/ST=London/L=London/O=example/OU=IT Department/CN=example.example" > /dev/null 2>&1
    if [ $? -ne 0 ]
    then
      echo 'Can not create certificate. Abort!'
      exit 1
    fi
    sed -r -i "s/(certificate_fingerprint:).*/\1 $(openssl x509 -fingerprint -in $CERTIFICATE_CRT_PATH | grep -i "fingerprint" | sed -r 's/^.*=//' | tr ':' ' ')/" $CONFIG_FILE
    echo 'Server certificate successfully generated!'
}

function parseYaml {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

function buildApkInDockerContainer {
        local isInitialBuild=0

        for arg in "$@"
        do
            if [ "$arg" == "--initial-build" ]
            then
                isInitialBuild=1
            fi
        done

        if [ "$isInitialBuild" -eq 0 ]
        then
            cordova --no-telemetry clean
        fi

        APK_FILE=$(cordova --no-telemetry build android  | egrep -i "/camera/platforms/android")
        if [ -z "$APK_FILE" ]
        then
          echo "Can not build .apk file. Abort!"
          exit 1
        fi

        if [ "$isInitialBuild" -eq 0 ]
        then
            #copy file to current directory
            cp $APK_FILE /camera-apk/camera-client-android.apk
            chmod 666 /camera-apk/camera-client-android.apk
            echo 'Android client "camera-client-android.apk" successfully created!'
        fi
}

# execute
main "$@"