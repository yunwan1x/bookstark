(() => {
    const video = document.querySelector('video');
    let engine, timer, tick, started = false, done = false, decoded = 0;
    const abort = new AbortController();
    function cleanup() {
        clearTimeout(timer); clearInterval(tick); abort.abort();
        if (engine) engine.destroy();
        video.pause(); video.removeAttribute('src'); video.load();
    }
    function report(ok, message) {
        if (done) return;
        done = true;
        clearInterval(tick); clearTimeout(timer);
        parent.postMessage({type:'tv-preview-result',ok,message}, location.origin);
        if (!ok) cleanup();
    }
    window.addEventListener('pagehide', cleanup, {once:true});
    window.addEventListener('message', async event => {
        if (event.source !== parent || event.origin !== location.origin || event.data?.type !== 'tv-preview' || started) return;
        started = true;
        timer = setTimeout(() => report(false,'未检测到持续画面。请检查播放地址、跨域许可或频道权限。'),35000);
        try {
            const {source, resolved} = event.data;
            const media = resolved || await SuperliveResolvers.resolve(source,{signal:abort.signal});
            if (done || abort.signal.aborted) return;
            const url = new URL(media.url);
            if (url.protocol !== 'https:' || url.username || url.password || media.referer || media.userAgent || Object.keys(media.headers||{}).length) throw Error('此线路不支持浏览器直接播放');
            if (/\.(mp4|webm)$/i.test(url.pathname) && !media.transform) video.src = url.href;
            else if (Hls.isSupported()) {
                const settings = media.transform ? {fLoader:SuperliveTransforms.createFragmentLoader(media.transform,Hls)} : {};
                engine = new Hls(settings);
                engine.on(Hls.Events.ERROR,(_,e)=>{if(e.fatal) report(false,'播放失败：'+e.details)});
                engine.attachMedia(video); engine.loadSource(url.href);
            } else if (!media.transform && video.canPlayType('application/vnd.apple.mpegurl')) video.src=url.href;
            else throw Error('当前浏览器不支持这条线路的格式');
            video.onerror=()=>report(false,'视频解码或网络请求失败');
            if (video.requestVideoFrameCallback) {
                const frame=()=>{decoded++;if(!done)video.requestVideoFrameCallback(frame)};
                video.requestVideoFrameCallback(frame);
            }
            let baseline;
            tick=setInterval(()=>{
                const frames=video.getVideoPlaybackQuality?.().totalVideoFrames || video.webkitDecodedFrameCount || decoded;
                if(!video.videoWidth || !frames || video.paused) return;
                if(!baseline) baseline={time:video.currentTime,frames};
                if(video.currentTime-baseline.time>=1 && frames>baseline.frames+2)
                    report(true,'已出画面 · '+video.videoWidth+' × '+video.videoHeight+' · 视频帧持续推进，请核对台标。');
            },250);
            await video.play();
        } catch (e) { if (!abort.signal.aborted) report(false,e.message || '线路试播失败'); }
    });
})();
