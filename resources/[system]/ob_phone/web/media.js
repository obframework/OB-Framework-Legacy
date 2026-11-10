(function(){
  const nativeConsoleLog=console.log.bind(console);
  console.log=(...args)=>{
    const message=String(args[0]??'');
    if(message==='f?'||message.startsWith('THREE.WebGLRenderer'))return;
    nativeConsoleLog(...args);
  };
  let canvas,context,glCanvas,renderer,target,scene,camera,material,geometry,gameTexture;
  let frame,lastFrame=0,pixels,imageData,recorder,chunks=[],started=0,videoAudioStream,audioRecorder,audioChunks=[],audioStream;
  let width=360,height=640;
  const frameInterval=1000/24;

  function disposeRenderer(){
    geometry?.dispose();material?.dispose();gameTexture?.dispose();target?.dispose();renderer?.dispose();
    glCanvas?.remove();glCanvas=null;
    renderer=target=scene=camera=material=geometry=gameTexture=null;pixels=imageData=null;
  }

  function render(now=0){
    if(!renderer||!canvas)return;
    frame=requestAnimationFrame(render);
    if(now-lastFrame<frameInterval)return;
    lastFrame=now;
    renderer.clear();renderer.render(scene,camera,target,true);
    renderer.readRenderTargetPixels(target,0,0,width,height,pixels);
    context.putImageData(imageData,0,0);
  }

  async function start(targetCanvas,options={}){
    stopView();
    if(!window.THREE?.CfxTexture)throw new Error('cfx_texture_unavailable');
    const landscape=options.landscape===true,front=options.front===true;
    width=landscape?854:480;height=landscape?480:854;
    canvas=targetCanvas;canvas.width=width;canvas.height=height;
    context=canvas.getContext('2d',{alpha:false,desynchronized:true});
    if(!context)throw new Error('game_view_unavailable');

    const THREE=window.THREE;glCanvas=document.createElement('canvas');
    glCanvas.style.cssText='position:fixed;left:-4px;top:-4px;width:1px;height:1px;opacity:0;pointer-events:none';
    document.body.appendChild(glCanvas);
    renderer=new THREE.WebGLRenderer({canvas:glCanvas,alpha:false,antialias:false,preserveDrawingBuffer:false});
    renderer.setPixelRatio(1);renderer.setSize(width,height,false);renderer.autoClear=false;
    target=new THREE.WebGLRenderTarget(width,height,{minFilter:THREE.LinearFilter,magFilter:THREE.NearestFilter,format:THREE.RGBAFormat,type:THREE.UnsignedByteType});
    camera=new THREE.OrthographicCamera(width/-2,width/2,height/2,height/-2,-10000,10000);camera.position.z=100;
    scene=new THREE.Scene();gameTexture=new THREE.CfxTexture();gameTexture.needsUpdate=true;
    material=new THREE.ShaderMaterial({
      uniforms:{tDiffuse:{value:gameTexture}},
      vertexShader:landscape?'varying vec2 vUv;void main(){vUv=vec2(uv.x,1.0-uv.y);gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0);}':'varying vec2 vUv;void main(){float crop=0.31615925;vUv=vec2(0.5+(uv.x-0.5)*crop,1.0-uv.y);gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0);}',
      fragmentShader:'varying vec2 vUv;uniform sampler2D tDiffuse;void main(){gl_FragColor=texture2D(tDiffuse,vUv);}'
    });
    geometry=new THREE.PlaneBufferGeometry(width,height);
    const quad=new THREE.Mesh(geometry,material);quad.position.z=-100;scene.add(quad);
    pixels=new Uint8Array(width*height*4);imageData=new ImageData(new Uint8ClampedArray(pixels.buffer),width,height);
    lastFrame=0;frame=requestAnimationFrame(render);
  }

  function stopView(){
    if(frame)cancelAnimationFrame(frame);frame=0;
    if(recorder&&recorder.state!=='inactive')recorder.stop();
    recorder?.stream?.getTracks().forEach(track=>track.stop());
    videoAudioStream?.getTracks().forEach(track=>track.stop());videoAudioStream=null;
    recorder=null;chunks=[];disposeRenderer();canvas=null;context=null;
  }

  function photo(){
    if(!canvas||!renderer)throw new Error('camera_inactive');
    return new Promise((resolve,reject)=>canvas.toBlob(blob=>blob?resolve(blob):reject(new Error('capture_failed')),'image/jpeg',.92));
  }

  function videoStream(fps=20){
    if(!canvas||!renderer||typeof canvas.captureStream!=='function')throw new Error('video_stream_unavailable');
    return canvas.captureStream(Math.max(12,Math.min(24,Number(fps)||20)));
  }

  async function startVideo(){
    if(!canvas||typeof MediaRecorder==='undefined')throw new Error('video_unsupported');
    if(!navigator.mediaDevices?.getUserMedia)throw new Error('microphone_unavailable');
    try{
      videoAudioStream=await navigator.mediaDevices.getUserMedia({audio:{echoCancellation:true,noiseSuppression:true,autoGainControl:true}});
    }catch{
      throw new Error('microphone_permission_required');
    }
    const audioTracks=videoAudioStream.getAudioTracks();
    if(!audioTracks.length){videoAudioStream.getTracks().forEach(track=>track.stop());videoAudioStream=null;throw new Error('microphone_unavailable')}
    let stream;
    try{
      stream=canvas.captureStream(24);
      audioTracks.forEach(track=>stream.addTrack(track));
      const mime=['video/webm;codecs=vp9,opus','video/webm;codecs=vp8,opus','video/webm'].find(type=>MediaRecorder.isTypeSupported(type))||'video/webm';
      chunks=[];recorder=new MediaRecorder(stream,{mimeType:mime,videoBitsPerSecond:2500000,audioBitsPerSecond:128000});
    }catch(error){
      stream?.getTracks().forEach(track=>track.stop());videoAudioStream?.getTracks().forEach(track=>track.stop());videoAudioStream=null;throw error
    }
    recorder.ondataavailable=event=>{if(event.data.size)chunks.push(event.data)};
    recorder.start(250);started=Date.now();
  }

  function stopVideo(){
    return new Promise((resolve,reject)=>{
      if(!recorder||recorder.state==='inactive')return reject(new Error('not_recording'));
      const current=recorder;
      const cleanup=()=>{current.stream.getTracks().forEach(track=>track.stop());videoAudioStream?.getTracks().forEach(track=>track.stop());videoAudioStream=null};
      current.onerror=()=>{cleanup();recorder=null;chunks=[];reject(new Error('record_failed'))};
      current.onstop=()=>{
        const blob=new Blob(chunks,{type:current.mimeType||'video/webm'});
        cleanup();recorder=null;chunks=[];
        resolve({blob,duration:Date.now()-started});
      };
      current.stop();
    });
  }

  async function startAudio(){
    if(audioRecorder&&audioRecorder.state==='recording')throw new Error('audio_already_recording');
    if(!navigator.mediaDevices?.getUserMedia||typeof MediaRecorder==='undefined')throw new Error('microphone_unavailable');
    audioStream=await navigator.mediaDevices.getUserMedia({audio:true});audioChunks=[];
    const mime=MediaRecorder.isTypeSupported('audio/webm;codecs=opus')?'audio/webm;codecs=opus':'audio/webm';
    audioRecorder=new MediaRecorder(audioStream,{mimeType:mime,audioBitsPerSecond:96000});
    audioRecorder.ondataavailable=event=>{if(event.data.size)audioChunks.push(event.data)};audioRecorder.start(200);
  }

  function stopAudio(){
    return new Promise((resolve,reject)=>{
      if(!audioRecorder||audioRecorder.state==='inactive')return reject(new Error('audio_not_recording'));
      const current=audioRecorder;current.onerror=()=>reject(new Error('audio_record_failed'));
      current.onstop=()=>{const blob=new Blob(audioChunks,{type:current.mimeType||'audio/webm'});audioStream?.getTracks().forEach(track=>track.stop());audioRecorder=null;audioStream=null;audioChunks=[];resolve(blob)};
      current.stop();
    });
  }

  function cancelAudio(){
    if(audioRecorder&&audioRecorder.state!=='inactive'){audioRecorder.ondataavailable=null;audioRecorder.onstop=null;audioRecorder.stop()}
    audioStream?.getTracks().forEach(track=>track.stop());audioRecorder=null;audioStream=null;audioChunks=[];
  }

  window.OBMediaCapture={start,stopView,photo,videoStream,startVideo,stopVideo,startAudio,stopAudio,cancelAudio,recording:()=>!!recorder&&recorder.state==='recording',audioRecording:()=>!!audioRecorder&&audioRecorder.state==='recording'};
})();
