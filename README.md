#RemoteVideoWatcher

##Table of contents
  * [General description](#general-description)
  * [Example of real working application](#example-of-real-working-application)
  * [Requirements](#requirements)
    * [General](#general)
    * [Linux](#linux)
    * [Linux (Raspberry pi)](#linux-raspberry-pi)
    * [Windows](#windows)
  * [Usage](#usage)
    * [Initial setup](#initial-setup)
    * [Build server](#build-server)
    * [Build client](#build-client)
    * [Finally](#finally)
  * [How it works inside](#how-it-works-inside)
    * [Server](#server)
    * [Client](#client)
  * [Security](#security)
    * [Current state](#current-state)
    * [Solutions to get absolute security](#solutions-to-get-absolute-security)
  * [Known issues](#known-issues)
  * [Future improvements](#future-improvements)
  * [Questions and Contribution](#questions-and-contribution)
  * [License](#license)


##General description
RemoteVideoWatcher is an application for remote monitor and video surveillance. It's a very easy to use, cheap and powerful solution.<br /><br />
The app consists of two parts: a server daemon (can be any PC) and a client (Android application).<br /><br />
You shoud launch the server daemon at the computer where any count of webcameras already attached. Next you can build client (Android application), install it on your smartphone and start watching webcameras from anywhere. Also you can enable an additional feature at the server to be able to connect to any cameras using any web browser and entering IP address of the server.<br /><br />
**App Features:**<br />
+ Very easy process of customization and installation (only 1 command to create server and also 1 command to build Android application) 
+ You can transform any kind of computer (desktop, laptop, raspberry-pi) to a server, connect any count of webcameras to it and start watching them instantly
+ The app has a suitable Android client
+ You can switch between any webcameras to watch in real time very easy and quickly
+ You can connect any count of clients at the same time to one server to watch the cameras
+ Hight security and using only open source code. Every part of app (server part with mjpg-streamer program, Android client application) compiles and builds in real time and you can watch this process. Also "Docker virtualization" is used at the server to achieve even more security.<br /><br /><br />

##Example of real working application
TODO<br /><br /><br />

##Requirements
###General
At first you have to install **Docker** (https://docs.docker.com/engine/installation/#installation).<br /><br />
Docker is a program like a virtual machine. Using it we can provide hight security in general and also a very easy process to build a server and a client parts of this app.<br /><br />
When works with this app you shoudn't use **#sudo** on any commands which you execute. Because of this don't forget to add your current user to **#docker** group (describes on Docker's installation page).
###Linux
In addition to Docker you also have to install gawk and openssl.

```
sudo apt-get install gawk openssl
```

Thanks Docker your machine will be clean like usual. It can create "virtual machines" itself with necessary packages and programs inside.
###Linux (Raspberry pi)
You need the same programs installed as in a Linux section.<br /><br />
Apart from usual webcameras you also can connect raspberry-pi camera (don't forget to enable it in raspi-config).<br /><br />
My raspberry-pi uses Raspbian as the OS.
###Windows
This app doesn't work on Windows now.<br />
But I think it will be not so hard to make it works on Windows because Docker can work very well on Windows too.
<br /><br /><br />

##Usage
###Initial setup
Copy file **config.yml.dist** in **config.yml** and customize.<br /><br />
You can see next params in this file:<br />
* **"default_server_ip"** - this is IP address of server. You will be able to change this address in future in every client on settings page.<br />
* **"external_server_ip"** - it the second IP address of the same server. Every several seconds client tries connecting to the **"default_server_ip"** at first, then if it fails it tries connecting to **"external_server_ip"**. If client have been successfully connected through the first IP it will be a green circle at the top, a yellow one otherwise. You can't change this address anywhere in a client. Usually I have internal IP address under NAT like 192.168.100.100 (I write it in "default_server_ip"), and an extenal IP address (I write it in "external_server_ip") in some VDS with a forwarded port to my server. It give me capabilites to quickly connect to internal IP if I am at home (192.....) or all traffic go through VDS if I am use mobile internet as example. You can set this parameter "0" if you don't need it. <br />
* **"enable_static_server"** - if you set it to "1" you will be able to connect to the server through web browser (something like https://192.168.100.100) without having any android client.<br />
**Warning!** You shoud use this feature only if your server in the local network under NAT, otherwise anybody will be able to connect and start controling your cameras.<br /> 
* **"wss_client_port"** - it tells what port at the server use to make connections between server and clients using WebSocket. Usually you don't need to modify it.<br />
* **"cameras" section**. It's very important section. You should write here all cameras which you want to watch. If you set "has_revert_option" option there will be created option in setting windows in client to flip video from camera 180 degrees. Usually for webcameras it will be default line where you need only change number of video device. You can find all cameras connected to your PC using command **"find /dev/ | grep /dev/video*"**.
* **"token_crypt_phrase"** and **"certificate_fingerprint"** - you mustn't edit these parameters. They generates automatically at the first time when you build the server. They used to provide hight security to application.
<br /><br />


###Build server
Just do command

```
./camera-utility.sh build-server
```

If you execute this command for the first time it can take a long time. At first a **mjpg-streamer** will be cloned from github (https://github.com/jacksonliam/mjpg-streamer.git), then compiled. If you are under raspberry-pi it will create ARM version of program, otherwise an usual version will be created. <br /><br />
Then https certificate will be created to work through HTTPS protocol between clients and the server. Then a token_crypt_phrase for clients and the server will be generated randomly.  <br /><br />
Finally docker-image will be created and will be ready to use as a server.  <br /><br />
You can do this command many times. As example if you want change token_crypt_phrase between clients and the server you can do

```
./camera-utility.sh build-server --regenerate-token-crypt-phrase
```

It will be very quickly because we won't need to compile mjpg-streamer again or generate https certificates.
<br />

###Build client
You can create Android application only under X86-64 machine.<br /><br />
If you are going to build client on different machine than server (as example raspberry-pi will be as a server) you shoud synchronize config.yml at first (server and client should use the same **config.yml** file). <br /><br />
Next do command 

```
./camera-utility.sh build-client
```

The process will take some time. Also it will take approximately 2GB of disk space. <br /><br />
A lot of programs and libraries will be downloaded and finally file **"camera-client-android.apk"** will be created in a root directory. <br />
You can install it on your devices and start using.
<br /><br />
###Finally
After all you should launch server application to start process clients and cameras. <br /><br />
You can do it by one command

```
./camera-utility.sh start-server-daemon
```


After this you will be able to connect to the server. <br /><br />
> **I recommend add this command to your autorun script (/etc/rc.local as example) in order to automatically launch server at every computer start**

<br /><br />

##How it works inside
###Server
The main part of the app is a server. <br />
It uses NodeJS and WebSockets. <br />
Also the server uses mjpg-streamer program to get video from webcameras.<br />
The server manages clients and sends videos from cameras to them.<br /><br />

###Client
Any count of clients can connect (through WebSockets) to the server and start switching between cameras and watch them.<br />
Also you can enable an additional feature in **config.yml** to connect to the server through web browser (something like https://192.168.100.100).<br />
You can use this feature when you don't have Andoid devices or as example when you sit at the computer and want to watch cameras right now.<br />
I use this app at home most of the time. Obviously I have router at home. And my server has local IP address like 192.168.100.100. You can customize this address right on client device in settings.
<br /><br /><br />

##Security
It's very important to provide hight security to any programs like this.  <br /> Otherwise anybody can connect to your server and watch your cameras.  <br />

###Current state
+ All communication and exchanging videos and commands go through HTTPS connection. So it will be 100% encrypted and nobody can see your traffic
+ When clients send something to the server (usually these are commands about switching cameras) they must provide access-token (token) to server with every request
+ The server doesn't send any videos from cameras to the client and also doesn't listen to clients' commands if the client doesn't send correct token in every request
+ Every short period of time the server checks if client didn't send correct token the server disconnect it
+ File config.yml has a parameter "token_crypt_phrase". This parameter generates automatically at first time when you build the server. This parameter then stored at the server and at the client applications.<br />
Every short period of time the server creates new token, crypts it using AES algorithm and "token_crypt_phrase" and finally send to clients. The client has to decrypt this token using the same "token_crypt_phrase" and sends it in every request to the server
+ Nobody can become the fake-client and start spying you because nobody knows your server/client "token_crypt_phrase" to decrypt token from the server

Now about sad things - ssl pinning and "Man in the Middle" attack. <br /> It's no any absolute way to prevent this attack on cordova and Android application. When you start connecting to the server "MITM" can become as proxy and listen to all traffic. This app uses https://github.com/EddyVerbruggen/SSLCertificateChecker-PhoneGap-Plugin to try preventing MITM.<br />
**This check occures only on Android application, not in browsers (on Desktop as example)** <br />

Every time when we want to connect to server from Android client this plugin make request to this IP and check certificate fingerprint. If it not equal to our certifitcate no connection will be established. <br />
It really must work appropriate way, but you shouldn't forget that a request about checking fingerprints and a request to connect to server are two distinct requests. And "MITM" can not touch the first request and intercepts the second request about connecting to the server and start listening your connection. And we will never known about this.<br /><br />
Let's summarize:<br />
+ "MITM" **can** listen to traffic (obviously that it's very hard to realise) between client and server **only in real time** during current session between you and the server
+ "MITM" **can not** connect to your server from anywhere at any time and start watching. It's because the client has to send token with every request to the server, and the fake-client can't do this because he can't decrypt token from the server without "token_crypt_phrase"
+ "MITM" **can not** intercept your connection and remains as a client in your system and watched your cameras forever. It's because server changes token every short period of time, and client has to decrypt this token and send back again and again forever.<br /><br />
So we can see that only the first point can been achieved by a hacker. But because of using **SSLCertificateChecker** even this hack is very hard to reproduce.
<br /><br />

###Solutions to get absolute security
+ Use app (server and clients) only inside one local secure network
+ Also you can achieve some kind of the above recommendation by using VPN. You can create own VPN or use commercial VPN, so you server can be situated at home and you will be able to watch cameras from smartphone from work as example
+ You can stop using HTTPS in this app and rewrite app to start using own cryptography for everything using RSA and AES together.  <br />
It's easy to do. I didn't do that only because I don't want to compicate source code (even it will be not so much code to implement cryptography) and also it's not a problem for me if "MITM" hypothetically will watch some finite time for my cameras together with me.
<br /><br /><br />

##Known issues
I founded a problem when you are watching cameras at mobile device the program consumes a lot of memory during some time. And in future can close itself with error. It occures because client gets a lot of images (video is transmitted as images) and every new image doesn't clear a previous one. It some kind of Webview error.<br />
But it not happend very often because it need a lot of time to take too much memory and also when you block device or explicitly close app memory is freed.
<br /><br /><br />

##Future improvements
Now when you build client Android application it has "debug" version. It means that it has some unnecessary debugging information for developer inside. It's not a problem because you are going to install and use this app only on your own devices. In future I will fix this and "release" version of application will be created every time.
<br /><br /><br />

##Questions and Contribution
I will be glad to answer any your questions. And I will certainly help you in any trouble about setup and launch my app. Don't hesitate and write me at aleksandr.dwt@gmail.com.<br />
Also it will be great if you make any proposal about any fixes or improvements.
<br /><br /><br />

##License
RemoteVideoWatcher is under the MIT license.
