// Exact HTTP/event stand using the real installed Socket.IO server, no production DB.
// Run: node local-relay-fixture.cjs /absolute/path/to/socket.io 33071
const http = require('node:http');
const {Server} = require(process.argv[2]);
// Match Electron's installed Socket.IO client, independently of the server version.
// This peer exercises the same event contract as Electron, not a packet mock.
const {io: javascriptClient} = require(require.resolve('socket.io-client', {paths:[process.argv[2] + '/..']}));
const port = Number(process.argv[3] || 33071);
const rooms = new Map();
const members = new Map();
let next = 0;
const peers = new Map();
const server = http.createServer(async (req,res) => {
  let raw=''; for await(const data of req) raw += data;
  const body=raw ? JSON.parse(raw) : {};
  const reply=(code,value)=>{res.writeHead(code,{'Content-Type':'application/json'});res.end(JSON.stringify(value));};
  if(req.url === '/fixture/js-peer' && req.method === 'POST') {
    if(body.action === 'connect') {
      const socket = javascriptClient(`http://127.0.0.1:${port}`, {transports:['websocket'], auth:{callsign:body.callsign}, reconnection:false});
      const peer = {socket, events:[]}; peers.set(body.callsign, peer);
      socket.onAny((name, value)=>peer.events.push({name, value}));
      try { await new Promise((resolve,reject)=>{socket.once('connect',resolve);socket.once('connect_error',reject);setTimeout(()=>reject(new Error('JS peer timeout')),3000).unref();}); }
      catch(error) { socket.disconnect(); return reply(500,{error:error.message}); }
      return reply(200,{ok:true});
    }
    const peer = peers.get(body.callsign);
    if(!peer) return reply(404,{error:'Unknown JS peer'});
    if(body.action === 'emit') peer.socket.emit(body.name,body.value);
    if(body.action === 'close') { peer.socket.disconnect(); peers.delete(body.callsign); }
    return reply(200,{events:peer.events});
  }
  if(req.url === '/api/auth/login' || req.url === '/api/auth/register') {
    if(body.password !== 'fixture-pass') return reply(401,{error:'Invalid callsign or password'});
    const callsign=body.callsign.toUpperCase(); return reply(200,{token:'fixture-'+callsign,user:{userId:callsign,callsign}});
  }
  if(req.url === '/api/lobbies' && req.method === 'GET') return reply(200,[...rooms.values()].map(r=>({...r,password:undefined})));
  if(req.url === '/api/lobbies' && req.method === 'POST') {
    if(!body.token?.startsWith('fixture-')) return reply(401,{error:'Unauthorized or invalid data'});
    if(body.name.trim().length<3) return reply(400,{error:'Lobby name must be between 3 and 30 characters'});
    const room={id:String(++next),name:body.name.trim(),owner:body.token.slice(8),hasPassword:!!body.password,password:body.password};rooms.set(room.id,room);
    reply(200,{id:room.id});io.emit('lobby_update');return;
  }
  if(req.url === '/fixture/drop' && req.method === 'POST') { for(const s of io.sockets.sockets.values()) if(s.data.callsign===body.callsign) s.conn.close(); return reply(200,{ok:true}); }
  reply(404,{error:'Not found'});
});
const io = new Server(server,{pingInterval:1000,pingTimeout:2000,...(process.argv[4]==='polling'?{transports:['polling']}:{})});
const update=id=>io.to(id).emit('room_update',{participants:[...(members.get(id)||new Map()).values()],owner:rooms.get(id)?.owner});
io.on('connection',socket=>{
  socket.emit('global_online',io.engine.clientsCount);
  socket.on('join',({roomId,password,token})=>{
    const room=rooms.get(roomId);if(!room) return socket.emit('error','Lobby not found');
    if(room.hasPassword && password!==room.password)return socket.emit('error','Invalid lobby password');
    if(!token?.startsWith('fixture-'))return socket.emit('error','Auth failed');
    const callsign=token.slice(8);socket.data.callsign=callsign;socket.data.room=roomId;socket.join(roomId);
    if(!members.has(roomId))members.set(roomId,new Map());
    members.get(roomId).set(callsign,{id:socket.id,userId:callsign,callsign});update(roomId);
  });
  socket.on('morse_event',({roomId,value})=>socket.to(roomId).emit('remote_morse',{callsign:socket.data.callsign,value}));
  socket.on('start_session',({roomId})=>io.to(roomId).emit('session_started',{turnOwnerId:rooms.get(roomId)?.owner}));
  const leave=id=>{members.get(id)?.delete(socket.data.callsign);socket.leave(id);io.to(id).emit('session_ended');update(id);};
  socket.on('leave_room',({roomId})=>leave(roomId));socket.on('disconnect',()=>{if(socket.data.room)leave(socket.data.room);});
});
server.listen(port,'127.0.0.1',()=>console.log(`fixture ready ${port}; Socket.IO ${require(process.argv[2]+'/package.json').version}`));
process.on('SIGTERM',()=>{io.close();server.close();});
