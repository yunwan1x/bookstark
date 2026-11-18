/* SuperLive public endpoint adapters. No accounts, embedded signing keys or proxy.
 * Resolution is not a playback guarantee: stream CORS/codecs still need testing.
 */
(() => {
  'use strict';
  const catalog = {
    sxrtv: {
      defaultId: 'sxws', ids: {sxws:'q8RVWgs',sxhh:'lce1mC4',sxjj:'4j01KWX',sxys:'Md571Kv',sxshfz:'p4y5do9',sxgg:'Y00Xezi'},
      endpoint: id => 'https://dyhhplus.sxrtv.com/apiv4.5/api/m3u8_notoken?channelid=' + encodeURIComponent(id),
      read: data => data?.data?.address
    },
    gzstv: {
      defaultId: 'gzws', ids: {gzws:'ch01',gzgg:'ch02',gzys:'ch03',gzdz:'ch04',gzst:'ch05',gzkj:'ch06'},
      endpoint: id => 'https://api.gzstv.com/v1/tv/' + encodeURIComponent(id) + '/?fields=stream_url',
      read: data => data?.stream_url
    },
    fjtv: {
      defaultId: 'dnws', ids: {fjzh:'665248990102917120',dnws:'665248966136664064',fjxw:'665248914378952704',fjly:'665248752898248704',fjse:'665248553475870720',hxws:'665248523855695872'},
      endpoint: id => 'https://live.fjtv.net/m2o/channel/channel_info.php?channel_id=' + encodeURIComponent(id),
      read: data => data?.[0]?.m3u8
    },
    hnntv: {
      defaultId: 'hnws', ids: {hnws:'STHaiNan_channel_lywsgq',ssws:'STHaiNan_channel_ssws',hnzm:'jjpd',hnxw:'STHaiNan_channel_xwpd',hnsf:'ggpd',hnwl:'wlpd',hnse:'sepd'},
      endpoint: id => 'https://ps.hnntv.cn/ps/livePlayUrl?appCode=&token=&channelCode=' + encodeURIComponent(id),
      read: data => data?.resultSet?.[0]?.url
    }
  };
  class ResolverError extends Error {
    constructor(code, message) { super(message); this.name = 'ResolverError'; this.code = code; }
  }
  function rawSource(source) {
    return String(typeof source === 'string' ? source : source?.url || source?.original || '').trim();
  }
  function directSource(source) {
    try {
      const url = new URL(rawSource(source));
      return ['http:','https:'].includes(url.protocol) && !url.username && !url.password ? url : null;
    } catch { return null; }
  }
  function checkProtocol(url) {
    if (globalThis.location?.protocol === 'https:' && url.protocol === 'http:')
      throw new ResolverError('MIXED_CONTENT', '接口只提供 HTTP 播放地址，当前 HTTPS 页面无法播放此线路。');
    return {url:url.href};
  }
  function parse(source) {
    const raw = rawSource(source);
    const match = /^([a-z][a-z0-9]*):\/\/([^?$#\s]*)(?:\$[^\r\n]*)?$/i.exec(String(raw).trim());
    if (!match) return null;
    const scheme = match[1].toLowerCase(), spec = catalog[scheme];
    if (!spec) return null;
    const name = match[2] || spec.defaultId;
    const id = Object.hasOwn(spec.ids, name) ? spec.ids[name] : Object.values(spec.ids).includes(name) ? name : null;
    return id ? {scheme, spec, id} : null;
  }
  async function resolve(source, {signal} = {}) {
    if (signal?.aborted) throw signal.reason || new DOMException('Aborted', 'AbortError');
    const direct = directSource(source);
    if (direct) return checkProtocol(direct);
    const parsed = parse(source);
    if (!parsed) throw new ResolverError('UNSUPPORTED_SOURCE', '此线路尚无浏览器公开接口适配器。');
    if (signal?.aborted) throw signal.reason || new DOMException('Aborted', 'AbortError');
    const controller = new AbortController();
    let timedOut = false;
    const onAbort = () => controller.abort(signal.reason);
    signal?.addEventListener('abort', onAbort, {once:true});
    const timeout = setTimeout(() => {timedOut = true; controller.abort();}, 12000);
    try {
      let response;
      try {
        response = await fetch(parsed.spec.endpoint(parsed.id), {
          signal:controller.signal, mode:'cors', credentials:'omit', cache:'no-store', referrerPolicy:'no-referrer'
        });
      } catch (error) {
        if (signal?.aborted) throw signal.reason || error;
        if (timedOut) throw new ResolverError('TIMEOUT', '公开接口连接超时，请重试或切换线路。');
        throw new ResolverError('CORS_OR_NETWORK', '浏览器无法读取公开接口：可能是跨域限制或网络连接失败。');
      }
      if (!response.ok) throw new ResolverError('HTTP_ERROR', '公开接口返回 HTTP ' + response.status + '。');
      let data;
      try { data = await response.json(); }
      catch (error) {
        if (signal?.aborted) throw signal.reason || error;
        if (timedOut) throw new ResolverError('TIMEOUT', '公开接口响应读取超时。');
        throw new ResolverError('INVALID_JSON', '公开接口没有返回有效 JSON 数据。');
      }
      const candidate = parsed.spec.read(data);
      let url;
      try { url = new URL(typeof candidate === 'string' ? candidate.trim() : ''); }
      catch { throw new ResolverError('NO_STREAM', '公开接口当前未提供有效播放地址。'); }
      if (!['http:','https:'].includes(url.protocol) || url.username || url.password)
        throw new ResolverError('NO_STREAM', '公开接口返回了不受支持的播放地址。');
      // Keep the endpoint's protocol; silently upgrading HTTP can break streams.
      return checkProtocol(url);
    } finally {
      clearTimeout(timeout);
      signal?.removeEventListener('abort', onAbort);
    }
  }
  globalThis.SuperliveResolvers = Object.freeze({
    canResolve: source => Boolean(directSource(source) || parse(source)), resolve,
    schemes:Object.freeze(Object.keys(catalog)), ResolverError
  });
})();
