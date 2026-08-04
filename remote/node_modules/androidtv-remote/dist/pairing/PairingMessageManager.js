"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.pairingMessageManager = void 0;

require("core-js/modules/es.regexp.to-string.js");

require("core-js/modules/es.array.iterator.js");

require("core-js/modules/web.dom-collections.iterator.js");

var _protobufjs = _interopRequireDefault(require("protobufjs"));

var _systeminformation = require("systeminformation");

var path = _interopRequireWildcard(require("path"));

var _url = require("url");

function _getRequireWildcardCache(nodeInterop) { if (typeof WeakMap !== "function") return null; var cacheBabelInterop = new WeakMap(); var cacheNodeInterop = new WeakMap(); return (_getRequireWildcardCache = function _getRequireWildcardCache(nodeInterop) { return nodeInterop ? cacheNodeInterop : cacheBabelInterop; })(nodeInterop); }

function _interopRequireWildcard(obj, nodeInterop) { if (!nodeInterop && obj && obj.__esModule) { return obj; } if (obj === null || typeof obj !== "object" && typeof obj !== "function") { return { default: obj }; } var cache = _getRequireWildcardCache(nodeInterop); if (cache && cache.has(obj)) { return cache.get(obj); } var newObj = {}; var hasPropertyDescriptor = Object.defineProperty && Object.getOwnPropertyDescriptor; for (var key in obj) { if (key !== "default" && Object.prototype.hasOwnProperty.call(obj, key)) { var desc = hasPropertyDescriptor ? Object.getOwnPropertyDescriptor(obj, key) : null; if (desc && (desc.get || desc.set)) { Object.defineProperty(newObj, key, desc); } else { newObj[key] = obj[key]; } } } newObj.default = obj; if (cache) { cache.set(obj, newObj); } return newObj; }

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { default: obj }; }

var directory = (0, path.dirname)((0, _url.fileURLToPath)(require('url').pathToFileURL(__filename).toString()));

class PairingMessageManager {
  constructor() {
    this.root = _protobufjs.default.loadSync(path.join(directory, "pairingmessage.proto"));
    this.PairingMessage = this.root.lookupType("pairing.PairingMessage");
    this.Status = this.root.lookupEnum("pairing.PairingMessage.Status").values;
    this.RoleType = this.root.lookupEnum("RoleType").values;
    this.EncodingType = this.root.lookupEnum("pairing.PairingEncoding.EncodingType").values;
    (0, _systeminformation.system)().then(data => {
      pairingMessageManager.manufacturer = data.manufacturer;
      pairingMessageManager.model = data.model;
    });
  }

  create(payload) {
    var errMsg = this.PairingMessage.verify(payload);
    if (errMsg) throw Error(errMsg);
    var message = this.PairingMessage.create(payload);
    return this.PairingMessage.encodeDelimited(message).finish();
  }

  createPairingRequest(service_name) {
    return this.create({
      pairingRequest: {
        serviceName: service_name,
        clientName: this.model
      },
      status: this.Status.STATUS_OK,
      protocolVersion: 2
    });
  }

  createPairingOption() {
    return this.create({
      pairingOption: {
        preferredRole: this.RoleType.ROLE_TYPE_INPUT,
        inputEncodings: [{
          type: this.EncodingType.ENCODING_TYPE_HEXADECIMAL,
          symbolLength: 6
        }]
      },
      status: this.Status.STATUS_OK,
      protocolVersion: 2
    });
  }

  createPairingConfiguration() {
    return this.create({
      pairingConfiguration: {
        clientRole: this.RoleType.ROLE_TYPE_INPUT,
        encoding: {
          type: this.EncodingType.ENCODING_TYPE_HEXADECIMAL,
          symbolLength: 6
        }
      },
      status: this.Status.STATUS_OK,
      protocolVersion: 2
    });
  }

  createPairingSecret(secret) {
    return this.create({
      pairingSecret: {
        secret: secret
      },
      status: this.Status.STATUS_OK,
      protocolVersion: 2
    });
  }

  parse(buffer) {
    return this.PairingMessage.decodeDelimited(buffer);
  }

}

var pairingMessageManager = new PairingMessageManager();
exports.pairingMessageManager = pairingMessageManager;