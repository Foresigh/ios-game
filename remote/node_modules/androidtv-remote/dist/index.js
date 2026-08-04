"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.default = exports.RemoteKeyCode = exports.RemoteDirection = exports.AndroidRemote = void 0;

require("core-js/modules/es.promise.js");

var _CertificateGenerator = require("./certificate/CertificateGenerator.js");

var _PairingManager = require("./pairing/PairingManager.js");

var _RemoteManager = require("./remote/RemoteManager.js");

var _RemoteMessageManager = require("./remote/RemoteMessageManager.js");

var _events = _interopRequireDefault(require("events"));

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { default: obj }; }

function asyncGeneratorStep(gen, resolve, reject, _next, _throw, key, arg) { try { var info = gen[key](arg); var value = info.value; } catch (error) { reject(error); return; } if (info.done) { resolve(value); } else { Promise.resolve(value).then(_next, _throw); } }

function _asyncToGenerator(fn) { return function () { var self = this, args = arguments; return new Promise(function (resolve, reject) { var gen = fn.apply(self, args); function _next(value) { asyncGeneratorStep(gen, resolve, reject, _next, _throw, "next", value); } function _throw(err) { asyncGeneratorStep(gen, resolve, reject, _next, _throw, "throw", err); } _next(undefined); }); }; }

class AndroidRemote extends _events.default {
  constructor(host, options) {
    var _options$cert, _options$cert2;

    super();
    this.host = host;
    this.cert = {
      key: (_options$cert = options.cert) === null || _options$cert === void 0 ? void 0 : _options$cert.key,
      cert: (_options$cert2 = options.cert) === null || _options$cert2 === void 0 ? void 0 : _options$cert2.cert
    };
    this.pairing_port = options.pairing_port ? options.pairing_port : 6467;
    this.remote_port = options.remote_port ? options.remote_port : 6466;
    this.service_name = options.service_name ? options.service_name : "Service Name";
  }

  start() {
    var _this = this;

    return _asyncToGenerator(function* () {
      if (!_this.cert.key || !_this.cert.cert) {
        _this.cert = _CertificateGenerator.CertificateGenerator.generateFull(_this.service_name, 'CNT', 'ST', 'LOC', 'O', 'OU');
        _this.pairingManager = new _PairingManager.PairingManager(_this.host, _this.pairing_port, _this.cert, _this.service_name);

        _this.pairingManager.on('secret', () => _this.emit('secret'));

        var paired = yield _this.pairingManager.start().catch(error => {
          console.error(error);
        });

        if (!paired) {
          return;
        }
      }

      _this.remoteManager = new _RemoteManager.RemoteManager(_this.host, _this.remote_port, _this.cert);

      _this.remoteManager.on('powered', powered => _this.emit('powered', powered));

      _this.remoteManager.on('volume', volume => _this.emit('volume', volume));

      _this.remoteManager.on('current_app', current_app => _this.emit('current_app', current_app));

      _this.remoteManager.on('ready', () => _this.emit('ready'));

      _this.remoteManager.on('unpaired', () => _this.emit('unpaired'));

      yield new Promise(resolve => setTimeout(resolve, 1000));
      var started = yield _this.remoteManager.start().catch(error => {
        console.error(error);
      });
      return started;
    })();
  }

  sendCode(code) {
    return this.pairingManager.sendCode(code);
  }

  sendPower() {
    return this.remoteManager.sendPower();
  }

  sendAppLink(app_link) {
    return this.remoteManager.sendAppLink(app_link);
  }

  sendKey(key, direction) {
    return this.remoteManager.sendKey(key, direction);
  }

  getCertificate() {
    return {
      key: this.cert.key,
      cert: this.cert.cert
    };
  }

  stop() {
    this.remoteManager.stop();
  }

}

exports.AndroidRemote = AndroidRemote;
var RemoteKeyCode = _RemoteMessageManager.remoteMessageManager.RemoteKeyCode;
exports.RemoteKeyCode = RemoteKeyCode;
var RemoteDirection = _RemoteMessageManager.remoteMessageManager.RemoteDirection;
exports.RemoteDirection = RemoteDirection;
var _default = {
  AndroidRemote,
  CertificateGenerator: _CertificateGenerator.CertificateGenerator,
  RemoteKeyCode,
  RemoteDirection
};
exports.default = _default;