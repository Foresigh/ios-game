"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.PairingManager = void 0;

require("core-js/modules/es.regexp.to-string.js");

require("core-js/modules/es.promise.js");

require("core-js/modules/es.json.stringify.js");

require("core-js/modules/web.url.to-json.js");

require("core-js/modules/es.parse-int.js");

var _tls = _interopRequireDefault(require("tls"));

var _PairingMessageManager = require("./PairingMessageManager.js");

var _cryptoJs = _interopRequireDefault(require("crypto-js"));

var _events = _interopRequireDefault(require("events"));

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { default: obj }; }

function asyncGeneratorStep(gen, resolve, reject, _next, _throw, key, arg) { try { var info = gen[key](arg); var value = info.value; } catch (error) { reject(error); return; } if (info.done) { resolve(value); } else { Promise.resolve(value).then(_next, _throw); } }

function _asyncToGenerator(fn) { return function () { var self = this, args = arguments; return new Promise(function (resolve, reject) { var gen = fn.apply(self, args); function _next(value) { asyncGeneratorStep(gen, resolve, reject, _next, _throw, "next", value); } function _throw(err) { asyncGeneratorStep(gen, resolve, reject, _next, _throw, "throw", err); } _next(undefined); }); }; }

class PairingManager extends _events.default {
  constructor(host, port, certs, service_name) {
    super();
    this.host = host;
    this.port = port;
    this.chunks = Buffer.from([]);
    this.certs = certs;
    this.service_name = service_name;
  }

  sendCode(code) {
    console.debug("Sending code : ", code);
    var code_bytes = this.hexStringToBytes(code);
    var client_certificate = this.client.getCertificate();
    var server_certificate = this.client.getPeerCertificate();

    var sha256 = _cryptoJs.default.algo.SHA256.create();

    sha256.update(_cryptoJs.default.enc.Hex.parse(client_certificate.modulus));
    sha256.update(_cryptoJs.default.enc.Hex.parse("0" + client_certificate.exponent.slice(2)));
    sha256.update(_cryptoJs.default.enc.Hex.parse(server_certificate.modulus));
    sha256.update(_cryptoJs.default.enc.Hex.parse("0" + server_certificate.exponent.slice(2)));
    sha256.update(_cryptoJs.default.enc.Hex.parse(code.slice(2)));
    var hash = sha256.finalize();
    var hash_array = this.hexStringToBytes(hash.toString());
    var check = hash_array[0];

    if (check !== code_bytes[0]) {
      this.client.destroy(new Error("Bad Code"));
      return false;
    } else {
      this.client.write(_PairingMessageManager.pairingMessageManager.createPairingSecret(hash_array));
      return true;
    }
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
        console.debug("Start Pairing Connect");
        _this.client = _tls.default.connect(options, () => {
          console.debug(_this.host + " Pairing connected");
        });
        _this.client.pairingManager = _this;

        _this.client.on("secureConnect", () => {
          console.debug(_this.host + " Pairing secure connected ");

          _this.client.write(_PairingMessageManager.pairingMessageManager.createPairingRequest(_this.service_name));
        });

        _this.client.on('data', data => {
          var buffer = Buffer.from(data);
          _this.chunks = Buffer.concat([_this.chunks, buffer]);

          if (_this.chunks.length > 0 && _this.chunks.readInt8(0) === _this.chunks.length - 1) {
            var message = _PairingMessageManager.pairingMessageManager.parse(_this.chunks);

            console.debug("Receive : " + Array.from(_this.chunks));
            console.debug("Receive : " + JSON.stringify(message.toJSON()));

            if (message.status !== _PairingMessageManager.pairingMessageManager.Status.STATUS_OK) {
              _this.client.destroy(new Error(message.status));
            } else {
              if (message.pairingRequestAck) {
                _this.client.write(_PairingMessageManager.pairingMessageManager.createPairingOption());
              } else if (message.pairingOption) {
                _this.client.write(_PairingMessageManager.pairingMessageManager.createPairingConfiguration());
              } else if (message.pairingConfigurationAck) {
                _this.emit('secret');
              } else if (message.pairingSecretAck) {
                console.debug(_this.host + " Paired!");

                _this.client.destroy();
              } else {
                console.debug(_this.host + " What Else ?");
              }
            }

            _this.chunks = Buffer.from([]);
          }
        });

        _this.client.on('close', hasError => {
          console.debug(_this.host + " Pairing Connection closed", hasError);

          if (hasError) {
            reject(false);
          } else {
            resolve(true);
          }
        });

        _this.client.on('error', error => {
          console.error(error);
        });
      });
    })();
  }

  hexStringToBytes(q) {
    var bytes = [];

    for (var i = 0; i < q.length; i += 2) {
      var byte = parseInt(q.substring(i, i + 2), 16);

      if (byte > 127) {
        byte = -(~byte & 0xFF) - 1;
      }

      bytes.push(byte);
    }

    return bytes;
  }

}

exports.PairingManager = PairingManager;