/*
* This file is part of the RemoteVideoWatcher package.
* (c) Alexander Lukashevich <aleksandr.dwt@gmail.com>
* For the full copyright and license information, please view the LICENSE file that was distributed with this source code.
*/

(function() {
	var WSS_SERVER_PORT = '%_wss_server_port_%';
	var TOKEN_CRYPT_PHRASE = '%_token_crypt_phrase_%';
	var ENABLE_STATIC_SERVER = '%_enable_static_server_%';

	var CAMERA_PORT = 6100;
	var STATIC_SERVER_PORT = 443;
	var CLIENT_CHECK_INACTIVE_DELAY = 30000;
	var CLIENT_MAX_INACTIVE_TIME = 50000;
	var REGENERATE_CLIENTS_TOKEN_TIME = 30000;

	var SERVER_WWW_PATH = '/camera/www';
	var SSL_CRT_FILE_PATH = '/camera/server/server.crt';
	var SSL_KEY_FILE_PATH = '/camera/server/server.key';
	var CAMERA_COMMAND = '/camera/server/cameras.sh';
	var NIGHT_PHOTO_ORIGINAL = '/camera/streamer/run/_camera_night_photo.jpg';
	var NIGHT_PHOTO_BRIGHT = '/camera/streamer/run/_camera_night_photo_bright.jpg';
	var CONVERT_IMAGE_COMMAND = '/usr/bin/convert -modulate 400,100,100 -quality 30'
		+ ' ' + NIGHT_PHOTO_ORIGINAL
		+ ' ' + NIGHT_PHOTO_BRIGHT;

	var currentCameraImage;
	var exec = require('child_process').exec;
	var WebSocketServer = require('ws').Server;
	var fs = require('fs');
	var aesjs = require('aes-js');
	var crypto = require('crypto');

	var wssClients = (function(){
		var clients = [];

		function closeClient(ws) {
			for (var i = 0; i < clients.length; i++) {
				if (clients[i]['ws'] === ws) {
					clients[i]['ws'].close();
					console.log('Closed client #' + i);
					break;
				}
			}
		}

		function disconnectInactiveClients() {
			var now = Date.now();

			for (var i = 0; i < clients.length; i++) {
				if (now - clients[i]['lastActivityTS']  > CLIENT_MAX_INACTIVE_TIME) {
					closeClient(clients[i]['ws']);
				}
			}
			setTimeout(disconnectInactiveClients, CLIENT_CHECK_INACTIVE_DELAY);
		}
		disconnectInactiveClients();

		return {
			getClientsCount: function() {
				var count = 0;
				for (var i = 0; i < clients.length; i++) {
					if (clients[i]['isVerified']) {
						count++;
					}
				}

				return count;
			},
			add: function(ws) {
				clients.push({
					ws: ws,
					lastActivityTS: Date.now(),
					isVerified: false
				});
				clientTokens.sendTokenToClients();
				console.log('Added client');
			},
			remove: function(ws) {
				for (var i = 0; i < clients.length; i++) {
					if (clients[i]['ws'] === ws) {
						clients.splice(i, 1);
						sendClientsCount();
						console.log('Removed client #' + i);
						break;
					}
				}
			},
			setVerified: function(ws) {
				for (var i = 0; i < clients.length; i++) {
					if (clients[i]['ws'] === ws) {
						if (!clients[i]['isVerified']) {
							clients[i]['isVerified'] = true;
							console.log('Set verified client #' + i);
							sendClientsCount();
							sendStatuses();
						}
						break;
					}
				}
			},
			updateLastActivity: function(ws) {
				for (var i = 0; i < clients.length; i++) {
					if (clients[i]['ws'] === ws) {
						clients[i]['lastActivityTS'] = Date.now();
						console.log('Set lastActivityTS client #' + i);
						break;
					}
				}
			},
			broadcast: function(data, sendToAll) {
				for (var i = 0; i < clients.length; i++) {
					if (sendToAll || clients[i]['isVerified']) {
						try {
							clients[i]['ws'].send(data);
							console.log('Sended to client #' + i + ': ' + data.length);
						} catch (e) { }
					}
				}
			},
			receiveMessage: function(ws, message) {
				console.log('Received message' + message);

				try {
					message = JSON.parse(message);
				} catch (e) {
					return;
				}

				// check "token"
				if (!clientTokens.isTokenValid(message)) {
					return;
				}

				// if message has valid "token" inside - we are verified
				wssClients.setVerified(ws);

				wssClients.updateLastActivity(ws);

				if (message.hasOwnProperty('toggle')) {
					exec(
						CAMERA_COMMAND + ' ' +
							(message.toggle.activate ? 'start' : 'stop') + ' ' +
							message.toggle.cameraId,
						function (error, stdout, stderr) {
							sendStatuses();
							if (error !== null) {
								console.log('stdout: ' + stdout);
								console.log('stderr: ' + stderr);
								console.log('exec error: ' + error);
							}
						}
					);
				}

			}
		};
	})();

	var clientTokens = (function () {
		var tokens = [createClientToken(), createClientToken()];

		function createClientToken() {
			return crypto.randomBytes(32).toString('hex');
		}

		function sendTokenToClients() {
			var aesCtr = new aesjs.ModeOfOperation.ctr(
				aesjs.util.convertStringToBytes(TOKEN_CRYPT_PHRASE)
			);
			var encryptedBytes = aesCtr
				.encrypt(aesjs.util.convertStringToBytes(tokens[1]))
				.toString('base64');

			wssClients.broadcast(
				JSON.stringify({ token: encryptedBytes }),
				true
			);
		}

		function regenerateClientsToken() {
			tokens.push(createClientToken());
			if (tokens.length > 2) {
				tokens.splice(0, 1);
			}

			sendTokenToClients();

			setTimeout(regenerateClientsToken, REGENERATE_CLIENTS_TOKEN_TIME);
		}
		regenerateClientsToken();

		return {
			sendTokenToClients: sendTokenToClients,
			isTokenValid: function (message) {
				if (!message.hasOwnProperty('token')) {
					return false;
				}

				return tokens.indexOf(message['token']) !== -1;
			}
		};
	})();
	
	// MJPG server listener
	(function(){
		var http = require('http'),
			request = null,
			boundary = '',
			data = '';
		
		function info(message) {
			console.log('MJPG server listener: ' + message);
		}
		
		function getBoundary(contentType) {
			var match = contentType.match(/multipart\/x-mixed-replace;\s*boundary=(.+)/);
			
			if ((match != null ? match.length : 0) > 1) {
				boundary = match[1];
			} else {
				boundary = '';
			}
		}
		
		function handleServerResponse(rawData) {
			var index = rawData.indexOf(boundary);
			var matches = rawData.match(/X-Timestamp:\s+\d+\.\d+\s+/);

			if (matches != null) {
				rawData = rawData.substring(rawData.indexOf(matches[0]) + matches[0].length);
			}

			if (index === -1) {
				data += rawData;
			} else {
				data += rawData.substring(0, index);
				info('downloaded image with size ' + data.length + ' bytes');
				currentCameraImage = data;
				data = '';
			}

			if (data.length >= 10000000) {
				currentCameraImage = data = '';
				info('clear image because of memory limit');
			}
		}
		
		function closeConnection() {
			request.end();
			request = null;
			currentCameraImage = data = '';
		}

		function createListener() {
			request = http.get(
				{
					port:CAMERA_PORT,
					host:'127.0.0.1',
					path:'/?action=stream'
				},
				function (response) {
					if (response.statusCode !== 200) {
						info('server did not respond with 200');
						closeConnection();
						return;
					}

					getBoundary(response.headers['content-type']);
					if (boundary === '') {
						info('error finding a boundary string');
						closeConnection();
						return;
					}

					data = '';

					response.setEncoding('binary');
					response.on('data', handleServerResponse);
					response.on('end', function () {
						info('server closed connection!');
						closeConnection();
					});
				}
			);

			request.on('error', function (error) {
				info(error.message);
				closeConnection();
			});
		}

		function updateCreatingListener() {
			if (request === null) {
				createListener();
			}
			setTimeout(updateCreatingListener, 5000);
		}
		
		// Start listening mjpg-streamer
		updateCreatingListener();
	})();

	if (ENABLE_STATIC_SERVER) {
		var nodeStatic = require('node-static');
		var fileServer = new nodeStatic.Server(SERVER_WWW_PATH);

		require('https').createServer({
				key  : fs.readFileSync(SSL_KEY_FILE_PATH),
				cert : fs.readFileSync(SSL_CRT_FILE_PATH)
			},
			function (request, response) {
				request.addListener('end', function () {
					fileServer.serve(request, response);
				}).resume();
			}).listen(STATIC_SERVER_PORT);
	}

	var server = require('https').createServer({
			key  : fs.readFileSync(SSL_KEY_FILE_PATH),
			cert : fs.readFileSync(SSL_CRT_FILE_PATH)
		},
		function (req, res) {
			res.writeHead(200);
			res.end();
		}).listen(WSS_SERVER_PORT);


	var wss = new WebSocketServer({ server: server });

	wss.on('connection', function(ws) {
		wssClients.add(ws);

		ws.on('close', function() {
			wssClients.remove(this);
		});

		ws.on('message', function(message) {
			wssClients.receiveMessage(this, message);
		});
	});

	/**
	 Send image
	 */
	function sendImage() {
		var data = currentCameraImage;
		if (data) {
			wssClients.broadcast(
				'data:image/jpeg;base64,' +
				new Buffer(data, 'binary').toString('base64')
			);
		}
		setTimeout(sendImage, 500);
	}
	sendImage();

	function sendClientsCount() {
		wssClients.broadcast(
			JSON.stringify({
				clientsCount: wssClients.getClientsCount()
			})
		);
	}

	/**
	 * Send status
	 */
	function sendStatuses()
	{
		exec(
			CAMERA_COMMAND + ' get-active-camera-id',
			function (error, stdout, stderr) {
				if (error !== null) {
					console.log('stdout: ' + stdout);
					console.log('stderr: ' + stderr);
					console.log('exec error: ' + error);
				} else {
					wssClients.broadcast(JSON.stringify({
						statuses: {
							activeCameraId: parseInt(stdout)
						}
					}));
				}
			}
		);
	}




	function getNightPhoto() {
		fs.exists(NIGHT_PHOTO_ORIGINAL, function(exists) {
			if (exists) {
				//convert to bright
				fs.unlink(NIGHT_PHOTO_BRIGHT, function() {
					exec(
						CONVERT_IMAGE_COMMAND, function () {
							fs.readFile(NIGHT_PHOTO_BRIGHT, function (err, data) {
								currentCameraImage = err ? '' : data;
								fs.unlink(NIGHT_PHOTO_ORIGINAL, function() {
									setTimeout(getNightPhoto, 1000);
								});
							});
						}
					);
				});
			} else {
				setTimeout(getNightPhoto, 1000);
			}
		});
	}
	getNightPhoto();




}).call(this);