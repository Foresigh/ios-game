"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.CertificateGenerator = void 0;

require("core-js/modules/es.regexp.to-string.js");

var _nodeForge = _interopRequireDefault(require("node-forge"));

var _crypto = _interopRequireDefault(require("crypto"));

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { default: obj }; }

class CertificateGenerator {
  static generateFull(name, country, state, locality, organisation, OU) {
    var keys = _nodeForge.default.pki.rsa.generateKeyPair(2048);

    var cert = _nodeForge.default.pki.createCertificate();

    cert.publicKey = keys.publicKey;
    cert.serialNumber = '01' + _crypto.default.randomBytes(19).toString("hex");
    cert.validity.notBefore = new Date();
    var date = new Date();
    date.setUTCFullYear(2099);
    cert.validity.notAfter = date;
    var attributes = [{
      name: 'commonName',
      value: name
    }, {
      name: 'countryName',
      value: country
    }, {
      shortName: 'ST',
      value: state
    }, {
      name: 'localityName',
      value: locality
    }, {
      name: 'organizationName',
      value: organisation
    }, {
      shortName: 'OU',
      value: OU
    }];
    cert.setSubject(attributes);
    cert.sign(keys.privateKey, _nodeForge.default.md.sha256.create());
    return {
      cert: _nodeForge.default.pki.certificateToPem(cert),
      key: _nodeForge.default.pki.privateKeyToPem(keys.privateKey)
    };
  }

}

exports.CertificateGenerator = CertificateGenerator;