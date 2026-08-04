"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.remoteMessageManager = void 0;

require("core-js/modules/es.regexp.to-string.js");

require("core-js/modules/es.array.iterator.js");

require("core-js/modules/web.dom-collections.iterator.js");

require("core-js/modules/es.json.stringify.js");

require("core-js/modules/web.url.to-json.js");

var _protobufjs = _interopRequireDefault(require("protobufjs"));

var _systeminformation = require("systeminformation");

var path = _interopRequireWildcard(require("path"));

var _url = require("url");

function _getRequireWildcardCache(nodeInterop) { if (typeof WeakMap !== "function") return null; var cacheBabelInterop = new WeakMap(); var cacheNodeInterop = new WeakMap(); return (_getRequireWildcardCache = function _getRequireWildcardCache(nodeInterop) { return nodeInterop ? cacheNodeInterop : cacheBabelInterop; })(nodeInterop); }

function _interopRequireWildcard(obj, nodeInterop) { if (!nodeInterop && obj && obj.__esModule) { return obj; } if (obj === null || typeof obj !== "object" && typeof obj !== "function") { return { default: obj }; } var cache = _getRequireWildcardCache(nodeInterop); if (cache && cache.has(obj)) { return cache.get(obj); } var newObj = {}; var hasPropertyDescriptor = Object.defineProperty && Object.getOwnPropertyDescriptor; for (var key in obj) { if (key !== "default" && Object.prototype.hasOwnProperty.call(obj, key)) { var desc = hasPropertyDescriptor ? Object.getOwnPropertyDescriptor(obj, key) : null; if (desc && (desc.get || desc.set)) { Object.defineProperty(newObj, key, desc); } else { newObj[key] = obj[key]; } } } newObj.default = obj; if (cache) { cache.set(obj, newObj); } return newObj; }

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { default: obj }; }

var directory = (0, path.dirname)((0, _url.fileURLToPath)(require('url').pathToFileURL(__filename).toString()));

class RemoteMessageManager {
  constructor() {
    this.root = _protobufjs.default.loadSync(path.join(directory, "remotemessage.proto"));
    this.RemoteMessage = this.root.lookupType("remote.RemoteMessage");
    this.RemoteKeyCode = this.root.lookupEnum("remote.RemoteKeyCode").values;
    this.RemoteDirection = this.root.lookupEnum("remote.RemoteDirection").values;
    (0, _systeminformation.system)().then(data => {
      this.manufacturer = data.manufacturer;
      this.model = data.model;
    });
  }

  create(payload) {
    if (!payload.remotePingResponse) {
      console.debug("Create Remote " + JSON.stringify(payload));
    }

    var errMsg = this.RemoteMessage.verify(payload);
    if (errMsg) throw Error(errMsg);
    var message = this.RemoteMessage.create(payload);
    var array = this.RemoteMessage.encodeDelimited(message).finish();

    if (!payload.remotePingResponse) {
      //console.debug("Sending " + Array.from(array));
      console.debug("Sending " + JSON.stringify(message.toJSON()));
    }

    return array;
  }

  createRemoteConfigure(code1, model, vendor, unknown1, unknown2) {
    return this.create({
      remoteConfigure: {
        code1: 622,
        deviceInfo: {
          model: this.model,
          vendor: this.manufacturer,
          unknown1: 1,
          unknown2: "1",
          packageName: "androitv-remote",
          appVersion: "1.0.0"
        }
      }
    });
  }

  createRemoteSetActive(active) {
    return this.create({
      remoteSetActive: {
        active: active
      }
    });
  }

  createRemotePingResponse(val1) {
    return this.create({
      remotePingResponse: {
        val1: val1
      }
    });
  }

  createRemoteKeyInject(direction, keyCode) {
    return this.create({
      remoteKeyInject: {
        keyCode: keyCode,
        direction: direction
      }
    });
  }

  createRemoteAdjustVolumeLevel(level) {
    return this.create({
      remoteAdjustVolumeLevel: level
    });
  }

  createRemoteResetPreferredAudioDevice() {
    return this.create({
      remoteResetPreferredAudioDevice: {}
    });
  }

  createRemoteImeKeyInject(appPackage, status) {
    return this.create({
      remoteImeKeyInject: {
        textFieldStatus: status,
        appInfo: {
          appPackage: appPackage
        }
      }
    });
  }

  createRemoteRemoteAppLinkLaunchRequest(app_link) {
    return this.create({
      remoteAppLinkLaunchRequest: {
        appLink: app_link
      }
    });
  }

  parse(buffer) {
    return this.RemoteMessage.decodeDelimited(buffer);
  }

}

var remoteMessageManager = new RemoteMessageManager();
exports.remoteMessageManager = remoteMessageManager;