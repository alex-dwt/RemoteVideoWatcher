/*
* This file is part of the RemoteVideoWatcher package.
* (c) Alexander Lukashevich <aleksandr.dwt@gmail.com>
* For the full copyright and license information, please view the LICENSE file that was distributed with this source code.
*/

(function(){
	var WSS_SERVER_PORT = '%_wss_server_port_%';
	var DEFAULT_IP_ADDRESS = '%_default_server_ip_%';
	var EXTERNAL_IP = '%_external_server_ip_%';
	var CERTIFICATE_FINGERPRINT = '%_certificate_fingerprint_%';
	var TOKEN_CRYPT_PHRASE = '%_token_crypt_phrase_%';
	var CAMERAS_LIST = [
//_list_of_cameras
	];

	var NO_PHOTO_URL = 'img/noPhoto.jpg';
	var CLIENT_SEND_PING_MESSAGE_DELAY = 30000;
	var CLEAR_CAMERA_IMAGE_DELAY = 4000;
	var CONNECT_TO_SERVER_DELAY = 3000;

	var ws;
	var $status;
	var $image;
	var storage = window.localStorage;
	var $optionsIpAddress;
	var isDesktop;
	var ipAddress;
	var clearCameraImageTimeout;
	var connectToServerTryCount = 0;
	var token = '';

	/**
	 *  Program entry point
	 */
	$(function() {
		if (
			document.URL.indexOf('http://') === -1
			&& document.URL.indexOf('https://') === -1
		) {
			isDesktop = false;
			document.addEventListener('deviceready', onDeviceReady, false);
		} else {
			isDesktop = true;
			onDeviceReady();
		}
	});

	var wsFunctions = {
		onerror: function() {
			ws.close();
		},
		onclose: function () {
			connectToServerTryCount++;
			token = '';

			$('.camera-switcher')
				.removeClass('ui-flipswitch-active')
				.addClass('disabled');

			$status.attr('data-status', 'closed').empty();
			setTimeout(
				function() {
					connectToServer((connectToServerTryCount % 2) ? null : EXTERNAL_IP);
				},
				CONNECT_TO_SERVER_DELAY
			);
		},
		onopen: function () {
			connectToServerTryCount = 0;

			$('.camera-switcher').removeClass('disabled');

			$status.attr(
				'data-status',
				EXTERNAL_IP !== '0' && ws.url.indexOf(EXTERNAL_IP) !== -1
					? 'remote'
					: 'home'
			);
		},
		onmessage: function(msg) {
			try {
				var message = JSON.parse(msg.data);

				//refresh clients number caption
				if (message.hasOwnProperty('clientsCount')){
					$status.text(message['clientsCount']);
				}

				// refresh session token
				if (message.hasOwnProperty('token')){
					var sendPing = !token;

					var aesCtr = new aesjs.ModeOfOperation.ctr(
						aesjs.util.convertStringToBytes(TOKEN_CRYPT_PHRASE)
					);
					token = aesjs.util.convertBytesToString(
						aesCtr.decrypt(Base64Binary.decode(message['token']))
					);

					if (sendPing) {
						sendPingMessage();
					}
				}

				//refresh toggles
				if (message.hasOwnProperty('statuses')) {
					var revertCamera = false;
					for (var i = 0, len = CAMERAS_LIST.length; i < len; i++) {
						if (message.statuses.activeCameraId == i) {
							CAMERAS_LIST[i]['el'].addClass('ui-flipswitch-active');

							//revert-option
							revertCamera = (
								typeof CAMERAS_LIST[i]['options']['revert'] !== 'undefined' &&
								CAMERAS_LIST[i]['options']['revert']
							);
						} else {
							CAMERAS_LIST[i]['el'].removeClass('ui-flipswitch-active');
						}
					}
					//revert-option
					$image.css('transform', revertCamera ? 'rotate(180deg)' : '');
				}

			} catch (e) {
				//camera image has been come
				if (clearCameraImageTimeout) {
					clearTimeout(clearCameraImageTimeout);
				}
				clearCameraImageTimeout = setTimeout(clearCameraImage, CLEAR_CAMERA_IMAGE_DELAY);

				$image.attr('src', msg.data);
			}
		}
	};

	function connectToServer(ip) {
		function connect() {
			ws = new WebSocket('wss://' + ip + ':' + WSS_SERVER_PORT);
			ws.binaryType = 'arraybuffer';
			ws.onerror = wsFunctions.onerror;
			ws.onclose = wsFunctions.onclose;
			ws.onopen = wsFunctions.onopen;
			ws.onmessage = wsFunctions.onmessage;
		}

		ip = ip || ipAddress;

		if (!ip) {
			return;
		}

		if (isDesktop) {
			connect();
		} else {
			window.plugins.sslCertificateChecker.check(
				function successCallback(message) {
					connect();
				},
				function errorCallback(message) {
					wsFunctions.onclose();
				},
				'https://' + ip + ':' + WSS_SERVER_PORT,
				CERTIFICATE_FINGERPRINT
			);
		}
	}

	function onDeviceReady() {
		if (!isDesktop) {
			keepscreenon.enable();
			FastClick.attach(document.body);
			document.addEventListener(
				'pause',
				function () {
					if (ws) {
						ws.close();
						ws = null;
					}
					if (navigator.app) {
						navigator.app.exitApp();
					}
					else if (navigator.device) {
						navigator.device.exitApp();
					}
				},
				false
			);
		}

		var clickEvent = isDesktop ? 'click' : 'touchend';

		/**
		 * Switchers
		 */
		//draw
		var $mainPageBody = $('#main-page-body');
		for (var i = CAMERAS_LIST.length - 1; i >= 0; i--) {
			CAMERAS_LIST[i]['el'] = $(
				'<div>\
					<div data-camera-id="' + i + '" class="disabled camera-switcher ui-flipswitch ui-shadow-inset ui-bar-inherit ui-corner-all">\
						<a href="#" class="ui-flipswitch-on ui-btn ui-shadow ui-btn-inherit">On</a>\
						<span class="ui-flipswitch-off">Off</span>\
					</div>\
					<p class="my-switch-caption">' + CAMERAS_LIST[i]['label'] + '</p>\
				</div>\
				<div style="clear: both"></div>'
			)
				.prependTo($mainPageBody)
				.find('[data-camera-id]')
				.eq(0);
		}

		//on click
		$mainPageBody.on(clickEvent, '.camera-switcher', function() {
			var $this = $(this);
			if (!$this.hasClass('disabled')) {
				$this.toggleClass('ui-flipswitch-active');
				sendMessage({
					toggle: {
						cameraId: $this.data('cameraId'),
						activate: CAMERAS_LIST[$this.data('cameraId')]['el'].hasClass('ui-flipswitch-active')
					}
				});
			}

			return false;
		});

		/**
		 * Options window
		 */
		//draw revert options
		var $optionsPageBody = $('#options-page-body');
		i = 0;
		for (var len = CAMERAS_LIST.length; i < len; i++) {
			if (typeof CAMERAS_LIST[i]['options']['revert'] !== 'undefined'){
				$optionsPageBody.append(
					'<label>\
						<input type="checkbox" class="revert-option-checkbox" data-camera-id="' + i + '">\
						Revert "' + CAMERAS_LIST[i]['label'] + '"\
					</label>'
				);
				//get saved value
				CAMERAS_LIST[i]['options']['revert'] = (
						storage.getItem('isCamera' + i + 'Revert') &&
						storage.getItem('isCamera' + i + 'Revert') === 'true'
					)
					? true
					: false;
			}
		}

		//IP address option
		$optionsIpAddress = $('#options-ip-address');
		ipAddress = storage.getItem('ip')
			? storage.getItem('ip')
			: DEFAULT_IP_ADDRESS;

		//open window - load saved options values
		$('#btn-options').on(clickEvent, function(){
			$optionsPageBody.find('.revert-option-checkbox').each(function(){
				var $this = $(this);
				var val = CAMERAS_LIST[$this.data('cameraId')]['options']['revert'];
				$this
					.prop('checked', val)
					.prev()
					.removeClass('ui-checkbox-on ui-checkbox-off')
					.addClass(val ? 'ui-checkbox-on' : 'ui-checkbox-off');
			});
			$optionsIpAddress.val(ipAddress);
		});

		//save options and close window
		$('#save-options-btn').on(clickEvent, function(){
			$optionsPageBody.find('.revert-option-checkbox').each(function(){
				var $this = $(this);
				var cameraId = $this.data('cameraId');
				CAMERAS_LIST[cameraId]['options']['revert'] = $this.prop('checked');
				storage.setItem(
					'isCamera' + cameraId + 'Revert',
					$this.prop('checked')
				);
			});

			ipAddress = $optionsIpAddress.val();
			storage.setItem('ip', ipAddress);

			$('[data-role=dialog]').dialog('close');
		});

		$status = $('#status');
		$image = $('#image').find('img').eq(0).attr('src', NO_PHOTO_URL);
		clearCameraImageTimeout = setTimeout(
			clearCameraImage,
			CLEAR_CAMERA_IMAGE_DELAY
		);

		//try connecting at program start
		connectToServer();

		//send PING to server
		function sendPing() {
			sendPingMessage();
			setTimeout(sendPing, CLIENT_SEND_PING_MESSAGE_DELAY);
		}
		sendPing();
	}

	function clearCameraImage() {
		$image.attr('src', NO_PHOTO_URL);
		clearCameraImageTimeout = setTimeout(clearCameraImage, CLEAR_CAMERA_IMAGE_DELAY);
	}

	function sendPingMessage() {
		sendMessage({ ping: 1 });
	}

	function sendMessage(message) {
		message['token'] = token;

		try {
			ws.send(JSON.stringify(message));
		} catch(e) { }
	}

})();
