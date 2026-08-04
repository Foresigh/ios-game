"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.RemoteManager = void 0;

require("core-js/modules/es.promise.js");

require("core-js/modules/es.json.stringify.js");

require("core-js/modules/web.url.to-json.js");

var _tls = _interopRequireDefault(require("tls"));

var _RemoteMessageManager = require("./RemoteMessageManager.js");

var _events = _interopRequireDefault(require("events"));

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { default: obj }; }

function asyncGeneratorStep(gen, resolve, reject, _next, _throw, key, arg) { try { var info = gen[key](arg); var value = info.value; } catch (error) { reject(error); return; } if (info.done) { resolve(value); } else { Promise.resolve(value).then(_next, _throw); } }

function _asyncToGenerator(fn) { return function () { var self = this, args = arguments; return new Promise(function (resolve, reject) { var gen = fn.apply(self, args); function _next(value) { asyncGeneratorStep(gen, resolve, reject, _next, _throw, "next", value); } function _throw(err) { asyncGeneratorStep(gen, resolve, reject, _next, _throw, "throw", err); } _next(undefined); }); }; }

class RemoteManager extends _events.default {
  constructor(host, port, certs) {
    super();
    this.host = host;
    this.port = port;
    this.certs = certs;
    this.chunks = Buffer.from([]);
    this.error = null;
  }

  start() {
    var _this = this;

    return _asyncToGenerator(function* () {
      return new Promise((resolve, reject) => {
        var options = {
          key: _this.certs.key,
          cert: _this.certs.cert,
          port: _this.port,
          host: _this.host,
          rejectUnauthorized: false
        };
        console.debug("Start Remote Connect");
        _this.client = _tls.default.connect(options, () => {//console.debug("Remote connected")
        });

        _this.client.on('timeout', () => {
          console.debug('timeout');

          _this.client.destroy();
        }); // Le ping est reçu toutes les 5 secondes


        _this.client.setTimeout(10000);

        _this.client.on("secureConnect", () => {
          console.debug(_this.host + " Remote secureConnect");
          resolve(true);
        });

        _this.client.on('data', data => {
          var buffer = Buffer.from(data);
          _this.chunks = Buffer.concat([_this.chunks, buffer]);

          if (_this.chunks.length > 0 && _this.chunks.readInt8(0) === _this.chunks.length - 1) {
            var message = _RemoteMessageManager.remoteMessageManager.parse(_this.chunks);

            if (!message.remotePingRequest) {
              //console.debug(this.host + " Receive : " + Array.from(this.chunks));
              console.debug(_this.host + " Receive : " + JSON.stringify(message.toJSON()));
            }

            if (message.remoteConfigure) {
              _this.client.write(_RemoteMessageManager.remoteMessageManager.createRemoteConfigure(622, "Build.MODEL", "Build.MANUFACTURER", 1, "Build.VERSION.RELEASE"));

              _this.emit('ready');
            } else if (message.remoteSetActive) {
              _this.client.write(_RemoteMessageManager.remoteMessageManager.createRemoteSetActive(622));
            } else if (message.remotePingRequest) {
              _this.client.write(_RemoteMessageManager.remoteMessageManager.createRemotePingResponse(message.remotePingRequest.val1));
            } else if (message.remoteImeKeyInject) {
              _this.emit('current_app', message.remoteImeKeyInject.appInfo.appPackage);
            } else if (message.remoteImeBatchEdit) {
              console.debug("Receive IME BATCH EDIT" + message.remoteImeBatchEdit);
            } else if (message.remoteImeShowRequest) {
              console.debug("Receive IME SHOW REQUEST" + message.remoteImeShowRequest);
            } else if (message.remoteVoiceBegin) {//console.debug("Receive VOICE BEGIN" + message.remoteVoiceBegin);
            } else if (message.remoteVoicePayload) {//console.debug("Receive VOICE PAYLOAD" + message.remoteVoicePayload);
            } else if (message.remoteVoiceEnd) {//console.debug("Receive VOICE END" + message.remoteVoiceEnd);
            } else if (message.remoteStart) {
              _this.emit('powered', message.remoteStart.started);
            } else if (message.remoteSetVolumeLevel) {
              _this.emit('volume', {
                level: message.remoteSetVolumeLevel.volumeLevel,
                maximum: message.remoteSetVolumeLevel.volumeMax,
                muted: message.remoteSetVolumeLevel.volumeMuted
              }); //console.debug("Receive SET VOLUME LEVEL" + message.remoteSetVolumeLevel.toJSON().toString());

            } else if (message.remoteSetPreferredAudioDevice) {//console.debug("Receive SET PREFERRED AUDIO DEVICE" + message.remoteSetPreferredAudioDevice);
            } else if (message.remoteError) {
              //console.debug("Receive REMOTE ERROR");
              _this.emit('error', {
                error: message.remoteError
              });
            } else {
              console.log("What else ?");
            }

            _this.chunks = Buffer.from([]);
          }
        });

        _this.client.on('close', /*#__PURE__*/function () {
          var _ref = _asyncToGenerator(function* (hasError) {
            console.info(_this.host + " Remote Connection closed ", hasError);

            if (hasError) {
              reject(_this.error.code);

              if (_this.error.code === "ECONNRESET") {
                _this.emit('unpaired');
              } else if (_this.error.code === "ECONNREFUSED") {
                // L'appareil n'est pas encore prêt : on relance
                yield new Promise(resolve => setTimeout(resolve, 1000));
                yield _this.start().catch(error => {
                  console.error(error);
                });
              } else if (_this.error.code === "EHOSTDOWN") {// L'appareil est down, on ne fait rien
              } else {
                // Dans le doute on redémarre
                yield new Promise(resolve => setTimeout(resolve, 1000));
                yield _this.start().catch(error => {
                  console.error(error);
                });
              }
            } else {
              // Si pas d'erreur on relance. Si elle s'est éteinte alors une erreur empéchera de relancer encore
              yield new Promise(resolve => setTimeout(resolve, 1000));
              yield _this.start().catch(error => {
                console.error(error);
              });
            }
          });

          return function (_x) {
            return _ref.apply(this, arguments);
          };
        }());

        _this.client.on('error', error => {
          console.error(_this.host, error);
          _this.error = error;
        });
      });
    })();
  }

  sendPower() {
    this.client.write(_RemoteMessageManager.remoteMessageManager.createRemoteKeyInject(_RemoteMessageManager.remoteMessageManager.RemoteDirection.SHORT, _RemoteMessageManager.remoteMessageManager.RemoteKeyCode.KEYCODE_POWER));
  }

  sendKey(key, direction) {
    this.client.write(_RemoteMessageManager.remoteMessageManager.createRemoteKeyInject(direction, key));
  }

  sendAppLink(app_link) {
    this.client.write(_RemoteMessageManager.remoteMessageManager.createRemoteRemoteAppLinkLaunchRequest(app_link));
  }

  stop() {
    this.client.destroy();
  }

}

exports.RemoteManager = RemoteManager;