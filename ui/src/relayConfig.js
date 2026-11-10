// Relay server address. Override for local testing: VITE_RELAY_URL=http://localhost:3001 npm run dev
export const RELAY_URL = import.meta.env.VITE_RELAY_URL || 'https://sk1bid.ru';
