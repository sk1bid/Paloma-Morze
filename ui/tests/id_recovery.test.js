import { jest } from '@jest/globals';

/**
 * Logic replica of the self-healing ID recovery from App.jsx
 */
function recoverUser(user, participants) {
  if (user && !user.userId && !user.id && participants.length > 0) {
    const me = participants.find(p => p.callsign?.toUpperCase() === user.callsign?.toUpperCase());
    if (me && (me.userId || me.id)) {
      return { ...user, userId: me.userId || me.id };
    }
  }
  return null;
}

describe('ID Recovery Logic (Release Environment Simulation)', () => {
  test('should restore userId when local user object is missing it but found in network participants', () => {
    // 1. Arrange: Local state is "corrupted" (missing ID)
    const localUser = { callsign: 'R4UAB' };
    const networkParticipants = [
      { id: '12345', callsign: 'R3AAA' },
      { id: '67890', userId: 'usr_abc', callsign: 'R4UAB' }, // Server ground truth
    ];

    // 2. Act
    const recovered = recoverUser(localUser, networkParticipants);

    // 3. Assert
    expect(recovered).toBeDefined();
    expect(recovered.userId).toBe('usr_abc');
    expect(recovered.callsign).toBe('R4UAB');
  });

  test('should prioritize userId over id from network object', () => {
    const localUser = { callsign: 'TEST' };
    const networkParticipants = [
      { id: 'old_id', userId: 'new_id', callsign: 'TEST' }
    ];

    const recovered = recoverUser(localUser, networkParticipants);
    expect(recovered.userId).toBe('new_id');
  });

  test('should fall back to id if userId is not present in network object', () => {
    const localUser = { callsign: 'TEST' };
    const networkParticipants = [
      { id: 'only_id', callsign: 'TEST' }
    ];

    const recovered = recoverUser(localUser, networkParticipants);
    expect(recovered.userId).toBe('only_id');
  });

  test('should return null if no matching callsign is found in participants', () => {
    const localUser = { callsign: 'R4UAB' };
    const networkParticipants = [
      { id: '123', callsign: 'R3AAA' }
    ];

    const recovered = recoverUser(localUser, networkParticipants);
    expect(recovered).toBeNull();
  });

  test('should work regardless of case sensitivity', () => {
    const localUser = { callsign: 'r4uab' };
    const networkParticipants = [
      { userId: '67890', callsign: 'R4UAB' }
    ];

    const recovered = recoverUser(localUser, networkParticipants);
    expect(recovered).toBeDefined();
    expect(recovered.userId).toBe('67890');
  });
});
