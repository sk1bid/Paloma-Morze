// electron-builder afterPack hook: code-signs the macOS app bundle ourselves.
//
// Why: Squirrel.Mac (used by electron-updater) only installs an update whose
// signature satisfies the running app's designated requirement. An ad-hoc
// signature pins that requirement to one build's cdhash, so every update is
// rejected. Signing every release with the same (self-signed) certificate pins
// the requirement to the certificate instead, and updates validate.
//
// electron-builder only signs with identities macOS trusts, which a self-signed
// certificate is not, so signing is done here with codesign directly.
//
//   MAC_SIGN_IDENTITY  SHA-1 hash or name of the signing identity (unset: ad-hoc)
//   MAC_SIGN_KEYCHAIN  keychain that holds the identity (optional)
const { execFileSync } = require('child_process');
const path = require('path');

exports.default = async function macSign(context) {
  if (context.electronPlatformName !== 'darwin') return;

  const appName = `${context.packager.appInfo.productFilename}.app`;
  const appPath = path.join(context.appOutDir, appName);
  const identity = process.env.MAC_SIGN_IDENTITY || '-';
  const keychain = process.env.MAC_SIGN_KEYCHAIN;

  const args = ['--force', '--deep', '--sign', identity];
  if (keychain) args.push('--keychain', keychain);
  args.push(appPath);

  console.log(`  • signing ${appName} with ${identity === '-' ? 'ad-hoc signature' : `identity ${identity}`}`);
  execFileSync('codesign', args, { stdio: 'inherit' });
  execFileSync('codesign', ['--verify', '--deep', '--strict', appPath], { stdio: 'inherit' });
};
