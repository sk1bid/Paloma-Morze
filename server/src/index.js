import express from 'express';
import { createServer } from 'http';
import { Server } from 'socket.io';
import { PrismaClient } from '@prisma/client';
const roomSessions = new Map();
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import cors from 'cors';
import dotenv from 'dotenv';

dotenv.config();

const prisma = new PrismaClient();
const app = express();
app.use(express.json());
app.use(cors());

const httpServer = createServer(app);
const io = new Server(httpServer, {
  cors: {
    origin: "*", // In production, specify your domain
    methods: ["GET", "POST"]
  }
});

const JWT_SECRET = process.env.JWT_SECRET || 'morse-secret-key';

// --- Registration ---
app.post('/api/auth/register', async (req, res) => {
  const { callsign, password } = req.body;
  if (!callsign || !password) return res.status(400).json({ error: 'Missing fields' });

  // VALIDATION: Callsign (3-12 Alphanumeric)
  const callsignRegex = /^[a-zA-Z0-9]{3,12}$/;
  if (!callsignRegex.test(callsign)) {
    return res.status(400).json({ error: 'Callsign must be 3-12 alphanumeric characters' });
  }

  // VALIDATION: Password (min 6)
  if (password.length < 6) {
    return res.status(400).json({ error: 'Password must be at least 6 characters' });
  }

  try {
    const hashedPassword = await bcrypt.hash(password, 10);
    const user = await prisma.user.create({
      data: { callsign: callsign.toUpperCase(), passwordHash: hashedPassword }
    });
    const token = jwt.sign({ userId: user.id, callsign: user.callsign }, JWT_SECRET);
    res.json({ token, user: { userId: user.id, callsign: user.callsign } });
  } catch (e) {
    res.status(400).json({ error: 'Callsign already taken' });
  }
});

// --- Login ---
app.post('/api/auth/login', async (req, res) => {
  const { callsign, password } = req.body;
  const user = await prisma.user.findUnique({ where: { callsign: callsign?.toUpperCase() } });
  if (!user || !(await bcrypt.compare(password, user.passwordHash))) {
    return res.status(401).json({ error: 'Invalid callsign or password' });
  }
  const token = jwt.sign({ userId: user.id, callsign: user.callsign }, JWT_SECRET);
  res.json({ token, user: { userId: user.id, callsign: user.callsign } });
});

// --- Lobbies ---
app.get('/api/lobbies', async (req, res) => {
  try {
    const lobbies = await prisma.lobby.findMany({
      include: {
        owner: {
          select: { callsign: true }
        }
      }
    });
    
    const result = lobbies.map(l => ({ 
      id: l.id, 
      name: l.name, 
      owner: l.owner ? l.owner.callsign : '?', 
      hasPassword: !!l.passwordHash 
    }));
    
    res.json(result);
  } catch (err) {
    console.error('Error fetching lobbies:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/api/lobbies', async (req, res) => {
  const { name, password, token } = req.body;
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    const userId = decoded.userId;
    
    // VALIDATION: Lobby Name (3-30 chars)
    if (!name || name.trim().length < 3 || name.trim().length > 30) {
      return res.status(400).json({ error: 'Lobby name must be between 3 and 30 characters' });
    }

    // CHECK FOR DUPLICATES
    const existing = await prisma.lobby.findFirst({ 
      where: { name: name.trim(), active: true } 
    });
    if (existing) {
      return res.status(400).json({ error: 'Lobby with this name already exists' });
    }

    const passwordHash = password ? await bcrypt.hash(password, 10) : null;
    const lobby = await prisma.lobby.create({
      data: { 
        name: name.trim(), 
        passwordHash, 
        ownerId: userId // FIXED: Using proper foreign key
      }
    });
    res.json(lobby);
    io.emit('lobby_update'); // Notify everyone that a new room exists
  } catch (e) {
    console.error('Lobby create error:', e);
    res.status(401).json({ error: 'Unauthorized or invalid data' });
  }
});

// --- Socket.io Logic ---

const roomParticipants = new Map(); // roomId -> Array of {id, callsign}

const broadcastOnlineCount = () => {
  const uniqueCallsigns = new Set();
  for (const [id, socket] of io.of("/").sockets) {
    const callsign = socket.handshake.auth?.callsign;
    if (callsign) {
      uniqueCallsigns.add(callsign.toUpperCase());
    }
  }
  const count = uniqueCallsigns.size || io.engine.clientsCount;
  console.log(`[Relay] Broadcasting unique online count: ${count} (${Array.from(uniqueCallsigns).join(', ')})`);
  io.emit('global_online', count);
};

io.on('connection', (socket) => {
  console.log('User connected:', socket.id);
  // Send initial count only to this user immediately
  socket.emit('global_online', io.engine.clientsCount);
  broadcastOnlineCount();

  socket.on('join', async ({ roomId, password, token }) => {
    try {
      const decoded = jwt.verify(token, JWT_SECRET);
      const lobby = await prisma.lobby.findUnique({ 
        where: { id: roomId },
        include: { owner: { select: { callsign: true } } }
      });
      
      if (!lobby) return socket.emit('error', 'Lobby not found');
      
      if (lobby.passwordHash) {
        if (!password || !(await bcrypt.compare(password, lobby.passwordHash))) {
          return socket.emit('error', 'Invalid lobby password');
        }
      }

      socket.join(roomId);
      socket.data.user = decoded;
      socket.data.currentRoomId = roomId;
      
      // Update participants
      if (!roomParticipants.has(roomId)) roomParticipants.set(roomId, []);
      const participants = roomParticipants.get(roomId);
      
      // Check if user already in list to avoid duplicates on reconnect
      if (!participants.find(p => p.userId === decoded.userId)) {
        participants.push({ 
          id: socket.id, 
          callsign: decoded.callsign, 
          userId: decoded.userId 
        });
        roomParticipants.set(roomId, participants);
      }
      
      console.log(`${decoded.callsign} joined room ${roomId}`);
      io.to(roomId).emit('user_joined', { callsign: decoded.callsign });
      console.log(`[Relay] Room ${roomId} update. Participants:`, JSON.stringify(participants), 'Owner:', lobby.owner.callsign);
      io.to(roomId).emit('room_update', { participants, owner: lobby.owner.callsign });

      // Send current session state (turn owner) to the newly joined user
      const session = roomSessions.get(roomId);
      if (session) {
        socket.emit('turn_update', { turnOwnerId: session.turnOwnerId });
      }
    } catch (e) {
      socket.emit('error', 'Auth failed');
    }
  });

  socket.on('morse_event', ({ roomId, value }) => {
    socket.to(roomId).emit('remote_morse', {
      callsign: socket.data.user?.callsign,
      value
    });
  });

  socket.on('start_session', async ({ roomId }) => {
    console.log(`[Relay] start_session requested for room: ${roomId} by socket: ${socket.id}`);
    const lobby = await prisma.lobby.findUnique({ 
      where: { id: roomId },
      include: { owner: true }
    });
    
    if (!lobby) {
      console.log(`[Relay] start_session failed: Lobby ${roomId} not found.`);
      return socket.emit('error', 'Lobby not found');
    }
    
    const ownerId = lobby.ownerId || lobby.owner?.id;
    console.log(`[Relay] Starting session. Owner ID Resolved: ${ownerId}`);
    
    // Explicitly log structural issues
    if (!ownerId) {
      console.error(`[Relay] CRITICAL: Could not resolve ownerId for lobby. Full Object:`, JSON.stringify(lobby));
    }
    
    // Set initial turn to owner
    roomSessions.set(roomId, { turnOwnerId: ownerId });
    
    // BROADCAST: Explicitly include turnOwnerId in session_started for immediate sync
    io.to(roomId).emit('session_started', { turnOwnerId: ownerId });
    
    // Keep turn_update for compatibility
    io.to(roomId).emit('turn_update', { turnOwnerId: ownerId });
    console.log(`[Relay] Session started successfully for room ${roomId}. Broadcasted turn: ${ownerId}`);
  });

  socket.on('pass_turn', ({ roomId }) => {
    console.log(`[Relay] Turn pass requested for room: ${roomId}`);
    const participants = roomParticipants.get(roomId);
    const session = roomSessions.get(roomId);
    
    if (!participants || !session) {
      console.log(`[Relay] Error: No participants or session found for room ${roomId}`);
      return;
    }
    
    // Find index of current turn owner
    const currentIndex = participants.findIndex(p => p.userId === session.turnOwnerId);
    if (currentIndex === -1) {
      console.log(`[Relay] Error: Current owner ${session.turnOwnerId} not in participants list`);
      return;
    }
    
    // Next index (circular)
    const nextIndex = (currentIndex + 1) % participants.length;
    const nextOwner = participants[nextIndex];
    
    session.turnOwnerId = nextOwner.userId;
    console.log(`[Relay] Turn passed: ${participants[currentIndex].callsign} -> ${nextOwner.callsign}`);
    io.to(roomId).emit('turn_update', { turnOwnerId: nextOwner.userId });
  });

  socket.on('leave_room', async ({ roomId }) => {
    if (roomId) {
      socket.leave(roomId);
      const participants = roomParticipants.get(roomId);
      if (participants) {
        const remaining = participants.filter(p => p.id !== socket.id);
        roomParticipants.set(roomId, remaining);
        
        if (remaining.length === 0) {
          console.log(`Room ${roomId} is empty, deleting...`);
          roomParticipants.delete(roomId);
          roomSessions.delete(roomId);
          await prisma.lobby.delete({ where: { id: roomId } }).catch(e => console.error('Delete error:', e));
          io.emit('lobby_update'); // Notify everyone that a room is gone
        } else {
          // If a session was active, notify remaining people to end it
          io.to(roomId).emit('session_ended');
          
          const lobby = await prisma.lobby.findUnique({ where: { id: roomId } });
          let currentOwnerCallsign = '';
          
          if (lobby && socket.data.user && socket.data.user.userId === lobby.ownerId) {
            // Owner is leaving! Transfer to first remaining person
            const newOwner = remaining[0];
            console.log(`Transferring ownership of room ${roomId} to ${newOwner.callsign}`);
            await prisma.lobby.update({
              where: { id: roomId },
              data: { ownerId: newOwner.userId }
            });
            currentOwnerCallsign = newOwner.callsign;
          } else {
            // departed person was not owner, fetch current owner callsign
            const fullLobby = await prisma.lobby.findUnique({
              where: { id: roomId },
              include: { owner: { select: { callsign: true } } }
            });
            currentOwnerCallsign = fullLobby?.owner?.callsign;
          }

          io.to(roomId).emit('room_update', { participants: remaining, owner: currentOwnerCallsign });
        }
      }
    }
  });

  socket.on('disconnect', async () => {
    const roomId = socket.data.currentRoomId;
    if (roomId) {
      const participants = roomParticipants.get(roomId);
      if (participants) {
        const remaining = participants.filter(p => p.id !== socket.id);
        roomParticipants.set(roomId, remaining);
        
        if (remaining.length === 0) {
          console.log(`Room ${roomId} is empty after disconnect, deleting...`);
          roomParticipants.delete(roomId);
          roomSessions.delete(roomId);
          // Use deleteMany to avoid 404/P2025 errors if already gone
          await prisma.lobby.deleteMany({ where: { id: roomId } }).catch(e => console.error("Lobby cleanup error:", e));
          io.emit('lobby_update'); 
        } else {
          io.to(roomId).emit('session_ended');
          
          const lobby = await prisma.lobby.findUnique({ where: { id: roomId } });
          let currentOwnerCallsign = '';
          
          if (lobby && socket.data.user && socket.data.user.userId === lobby.ownerId) {
            const newOwner = remaining[0];
            console.log(`Transferring ownership of room ${roomId} to ${newOwner.callsign} after disconnect`);
            // Safe update
            await prisma.lobby.updateMany({
              where: { id: roomId },
              data: { ownerId: newOwner.userId }
            }).catch(e => console.error("Ownership transfer error:", e));
            currentOwnerCallsign = newOwner.callsign;
          } else {
            const fullLobby = await prisma.lobby.findUnique({
              where: { id: roomId },
              include: { owner: { select: { callsign: true } } }
            });
            currentOwnerCallsign = fullLobby?.owner?.callsign;
          }
          
          io.to(roomId).emit('room_update', { participants: remaining, owner: currentOwnerCallsign });
        }
      }
    }
    broadcastOnlineCount();
    console.log('User disconnected:', socket.id);
  });
});

const PORT = process.env.PORT || 3001;
httpServer.listen(PORT, () => {
  console.log(`Relay server running on port ${PORT}`);
});
