(function(){
  let peer=null,callId=null,initiator=false,localStream=null,remoteStream=null,front=true,starting=false,offering=false;
  const queued=new Map();
  const post=async(name,body={})=>{try{const response=await fetch('https://'+GetParentResourceName()+'/'+name,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});return await response.json()}catch{return{ok:false}}};
  const status=text=>{const node=document.querySelector('#videoCallStatus');if(node)node.textContent=text};
  const config=()=>({iceServers:Array.isArray(window.OBVideoIceServers)?window.OBVideoIceServers:[]});

  function bindRemote(){const video=document.querySelector('#remoteVideo');if(video&&remoteStream&&video.srcObject!==remoteStream){video.srcObject=remoteStream;video.play().catch(()=>{})}}
  function bindLocal(){const canvas=document.querySelector('#localVideo');if(canvas)canvas.classList.toggle('camera-off',localStream?.getVideoTracks().every(track=>!track.enabled)===true)}
  async function send(payload){if(callId!=null)await post('videoSignal',{callId,payload})}
  function createPeer(){
    const connection=new RTCPeerConnection(config());
    connection.onicecandidate=event=>{if(event.candidate)send({type:'candidate',candidate:event.candidate.toJSON?event.candidate.toJSON():event.candidate})};
    connection.ontrack=event=>{remoteStream=event.streams[0]||new MediaStream([event.track]);bindRemote();status('Vídeo conectado')};
    connection.onconnectionstatechange=()=>{const state=connection.connectionState;if(state==='connected')status('Vídeo conectado');else if(state==='failed'||state==='disconnected')status('Reconectando vídeo…')};
    return connection;
  }
  async function makeOffer(){
    if(!peer||offering||peer.signalingState!=='stable')return;
    offering=true;
    try{const offer=await peer.createOffer();await peer.setLocalDescription(offer);await send({type:'offer',sdp:peer.localDescription})}finally{offering=false}
  }
  async function start(options){
    const id=Number(options?.callId);
    if(!id||starting||document.querySelector('#phone')?.classList.contains('hidden'))return;
    if(callId===id&&peer){bindRemote();bindLocal();return}
    stop(true);starting=true;callId=id;initiator=options.initiator===true;front=true;
    try{
      if(typeof RTCPeerConnection==='undefined')throw new Error('webrtc_unavailable');
      const canvas=document.querySelector('#localVideo');if(!canvas)throw new Error('local_view_unavailable');
      window.OBVideoIceServers=options.iceServers||[];
      await post('cameraActive',{active:true,videoCall:true});await post('cameraFacing',{front:true});
      await window.OBMediaCapture.start(canvas,{landscape:false,front:true});
      localStream=window.OBMediaCapture.videoStream(24);peer=createPeer();
      for(const track of localStream.getVideoTracks()){
        const sender=peer.addTrack(track,localStream);
        if(sender?.getParameters&&sender?.setParameters){const parameters=sender.getParameters();parameters.encodings=parameters.encodings?.length?parameters.encodings:[{}];Object.assign(parameters.encodings[0],{maxBitrate:1800000,maxFramerate:24,scaleResolutionDownBy:1});parameters.degradationPreference='maintain-resolution';await sender.setParameters(parameters).catch(()=>{})}
      }
      bindLocal();
      status('Conectando vídeo…');await send({type:'ready',reply:false});
      const waiting=queued.get(id)||[];queued.delete(id);for(const payload of waiting)await signal(id,payload);
    }catch(error){status('Vídeo indisponível');console.error('[ob_phone] video call:',error)}finally{starting=false}
  }
  async function signal(id,payload){
    id=Number(id);if(!id||!payload)return;
    if(id!==callId||!peer){const list=queued.get(id)||[];if(list.length<40)list.push(payload);queued.set(id,list);return}
    try{
      if(payload.type==='ready'){
        if(payload.reply!==true)await send({type:'ready',reply:true});
        if(initiator)await makeOffer();
      }else if(payload.type==='offer'&&payload.sdp){
        await peer.setRemoteDescription(payload.sdp);const answer=await peer.createAnswer();await peer.setLocalDescription(answer);await send({type:'answer',sdp:peer.localDescription});
      }else if(payload.type==='answer'&&payload.sdp){await peer.setRemoteDescription(payload.sdp)
      }else if(payload.type==='candidate'&&payload.candidate){await peer.addIceCandidate(payload.candidate)}
    }catch(error){console.error('[ob_phone] video signal:',error);status('Reconectando vídeo…')}
  }
  function setCamera(enabled){if(localStream)localStream.getVideoTracks().forEach(track=>track.enabled=enabled===true);bindLocal()}
  async function flip(){front=!front;await post('cameraFacing',{front});const canvas=document.querySelector('#localVideo');if(canvas)await window.OBMediaCapture.start(canvas,{landscape:false,front})}
  function stop(silent=false){
    const oldId=callId;callId=null;initiator=false;starting=false;offering=false;
    if(peer){peer.onicecandidate=peer.ontrack=peer.onconnectionstatechange=null;peer.close()}peer=null;
    localStream?.getTracks().forEach(track=>track.stop());localStream=null;remoteStream=null;
    window.OBMediaCapture?.stopView?.();if(!silent&&oldId!=null)post('cameraActive',{active:false});
  }
  window.OBVideoCall={start,stop,signal,setCamera,flip,active:()=>callId!=null};
})();
