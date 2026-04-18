import express from 'express';
import { createServer } from 'http';
import { Server } from 'socket.io';
import { PrismaClient } from '@prisma/client';
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
    res.json({ token, user: { callsign: user.callsign } });
  } catch (e) {
    res.status(400).json({ error: 'Callsign already taken' });
  }
});

// --- Login ---
app.post('/api/auth/login', async (req, res) => {
  const { callsign, password } = req.body;
  const user = await prisma.user.findUnique({ where: { callsign: callsign?.toUpperCase() } });
  if (!user || !(await bcrypt.compare(password, user.passwordHash))) {
    return res.status(400).json({ error: 'Invalid credentials' });
  }
  const token = jwt.sign({ userId: user.id, callsign: user.callsign }, JWT_SECRET);
  res.json({ token, user: { callsign: user.callsign } });
});

// --- Lobbies ---
app.get('/api/lobbies', async (req, res) => {
  const lobbies = await prisma.lobby.findMany();
  res.json(lobbies.map(l => ({ id: l.id, name: l.name, owner: l.owner, hasPassword: !!l.passwordHash })));
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

io.on('connection', (socket) => {
  console.log('User connected:', socket.id);

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
      if (!participants.find(p => p.callsign === decoded.callsign)) {
        participants.push({ 
          id: socket.id, 
          callsign: decoded.callsign,
          userId: decoded.userId 
        });
      }
      
      console.log(`${decoded.callsign} joined room ${roomId}`);
      io.to(roomId).emit('user_joined', { callsign: decoded.callsign });
      io.to(roomId).emit('room_update', { participants, owner: lobby.owner.callsign });
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
    const lobby = await prisma.lobby.findUnique({ where: { id: roomId } });
    if (lobby && socket.data.user && socket.data.user.userId === lobby.ownerId) {
      io.to(roomId).emit('session_started');
    } else {
      socket.emit('error', 'Only the owner can start the session');
    }
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
          // Only attempt delete if it actually exists (avoid crash on double disconnect/race)
          await prisma.lobby.delete({ where: { id: roomId } }).catch(() => {});
          io.emit('lobby_update'); // Notify everyone that a room is gone
        } else {
          io.to(roomId).emit('session_ended');
          
          const lobby = await prisma.lobby.findUnique({ where: { id: roomId } });
          let currentOwnerCallsign = '';
          
          if (lobby && socket.data.user && socket.data.user.userId === lobby.ownerId) {
            // Owner disconnected! Transfer to first remaining person
            const newOwner = remaining[0];
            console.log(`Transferring ownership of room ${roomId} to ${newOwner.callsign} after disconnect`);
            await prisma.lobby.update({
              where: { id: roomId },
              data: { ownerId: newOwner.userId }
            });
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
    console.log('User disconnected:', socket.id);
  });
});

const PORT = process.env.PORT || 3001;
httpServer.listen(PORT, () => {
  console.log(`Relay server running on port ${PORT}`);
});
