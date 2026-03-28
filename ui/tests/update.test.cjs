const semver = require('semver');

/**
 * Logic replica of what the app should decide when it sees a new version.
 * @param {string} current Current app version
 * @param {string} remote Remote version from latest.yml
 */
function shouldUpdate(current, remote) {
  // If remote is strictly greater than current
  if (semver.gt(remote, current)) {
    return 'available';
  }
  // If they are equal or current is newer (dev build)
  return 'uptodate';
}

describe('Update Version Comparison Logic', () => {
  test('should notify when a newer version is available', () => {
    expect(shouldUpdate('0.1.0', '0.1.1')).toBe('available');
    expect(shouldUpdate('0.1.0-beta.25', '0.1.0-beta.26')).toBe('available');
  });

  test('should say uptodate when versions match', () => {
    expect(shouldUpdate('0.1.0', '0.1.0')).toBe('uptodate');
    expect(shouldUpdate('1.2.3', '1.2.3')).toBe('uptodate');
  });

  test('should ignore downgrades (local dev builds)', () => {
    expect(shouldUpdate('0.1.1-dev', '0.1.0')).toBe('uptodate');
    expect(shouldUpdate('0.2.0', '0.1.5')).toBe('uptodate');
  });
});
