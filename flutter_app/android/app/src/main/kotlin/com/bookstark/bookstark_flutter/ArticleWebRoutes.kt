package com.bookstark.bookstark_flutter

import android.net.Uri
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URI
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap

class ArticleWebRoutes(private val server: URI, private val cookiePath: String) {
    private val prefix = server.path.trimEnd('/')
    private val rawPrefix = server.rawPath.trimEnd('/')
    val origin = URI(server.scheme, null, server.host,
        if (server.port == (if (server.scheme == "https") 443 else 80)) -1 else server.port,
        null, null, null).toString()
    private val aliases = setOf("static", "api", "upload-files", "notes", "blogs",
        "manifest.json", "sw.js", "favicon.ico", "home", "books", "bookmarks",
        "topics", "images", "labels", "webdav", "profile", "trash", "login", "logout")
    private val connections = Collections.newSetFromMap(ConcurrentHashMap<HttpURLConnection, Boolean>())
    @Volatile private var closed = false
    private fun port(uri: URI) = if (uri.port >= 0) uri.port else if (uri.scheme == "https") 443 else 80
    fun sameOrigin(uri: URI): Boolean = uri.scheme == server.scheme &&
        uri.host.equals(server.host, true) && port(uri) == port(server) && uri.rawUserInfo == null
    private fun parse(value: String): URI? {
        if (value.length > 8192 || value.any { it.code < 32 || it == '\\' }) return null
        val uri = try { URI(value) } catch (_: Exception) { return null }
        if (uri.rawUserInfo != null || uri.scheme !in listOf("http", "https") || uri.host.isNullOrEmpty()) return null
        if (uri.rawPath.contains("//") || Regex("%(?:2f|5c|25)", RegexOption.IGNORE_CASE).containsMatchIn(uri.rawPath ?: "") ||
            uri.path.split('/').any { it == "." || it == ".." || it.contains('\\') ||
                it.any { c -> c.code < 32 || c.code == 127 } }) return null
        return uri
    }
    fun normalized(value: String, navigation: Boolean = false): URI? {
        val uri = parse(value) ?: return null
        if (!sameOrigin(uri)) return null
        if (prefix.isEmpty() || uri.path == prefix || uri.path.startsWith("$prefix/")) return if (navigation && relative(uri) == listOf("notes")) articleList(uri) else uri
        val first = uri.path.trimStart('/').substringBefore('/')
        if (first !in aliases || (!navigation && first in setOf("home", "books", "profile", "trash"))) return null
        val query = if (uri.rawQuery != null) "?${uri.rawQuery}" else ""
        val fragment = if (uri.rawFragment != null) "#${uri.rawFragment}" else ""
        return try { val mapped = URI("$origin$rawPrefix${uri.rawPath}$query$fragment"); if (navigation && relative(mapped) == listOf("notes")) articleList(mapped) else mapped } catch (_: Exception) { null }
    }
    private fun relative(uri: URI): List<String>? {
        if (!sameOrigin(uri)) return null
        if (prefix.isNotEmpty() && !uri.path.startsWith("$prefix/")) return null
        return uri.path.removePrefix(prefix).trimStart('/').split('/')
    }
    private fun articleList(uri: URI): URI? {
        val value = Uri.parse(uri.toString())
        if (listOf("tab", "type").any { value.getQueryParameters(it).size > 1 }) return null
        val tab = value.getQueryParameter("tab")
        val type = value.getQueryParameter("type")
        if ((tab != null && tab != "articles") || (type != null && type != "article")) return null
        val out = value.buildUpon().clearQuery()
        value.queryParameterNames.filter { it != "tab" && it != "type" }.forEach { key ->
            value.getQueryParameters(key).forEach { out.appendQueryParameter(key, it) }
        }
        out.appendQueryParameter("tab", "articles").appendQueryParameter("type", "article")
        return URI(out.build().toString())
    }
    fun validInitialEntry(value: String): Boolean {
        val uri = parse(value) ?: return false
        if (uri.rawFragment != null || !sameOrigin(uri)) return false
        val path = relative(uri) ?: return false
        if (path == listOf("notes")) return uri.rawQuery == "tab=articles&type=article"
        return uri.rawQuery == null && path.size == 3 && path[0] == "blogs" &&
            path[2] == "edit" && path[1].isNotEmpty() &&
            path[1].toByteArray(Charsets.UTF_8).size <= 256
    }
    fun isArticle(uri: URI): Boolean {
        val path = relative(uri) ?: return false
        return (path == listOf("notes") && articleList(uri) != null) || (path.size == 3 && path[0] == "blogs" && path[1].isNotEmpty() && path[2] == "edit")
    }
    fun isEditor(uri: URI): Boolean {
        val path = relative(uri) ?: return false
        return path.size == 3 && path[0] == "blogs" && path[2] == "edit"
    }
    fun isBodySource(uri: Uri): Boolean {
        val value = normalized(uri.toString()) ?: return false
        val path = relative(value) ?: return false
        return path.size == 5 && path[0] == "api" && path[1] == "blogs" &&
            path[2].all { it.isDigit() } && path[3] == "content" && path[4] == "raw"
    }
    fun denied(status: Int = 403): WebResourceResponse = WebResourceResponse("text/plain", "utf-8",
        status, if (status == 403) "Forbidden" else "Unavailable",
        mapOf("Cache-Control" to "no-store"), ByteArrayInputStream(ByteArray(0)))

    /** Root-alias GET/HEAD only. Native never retries or reconstructs an API POST. */
    fun resource(request: WebResourceRequest, cookies: CookieManager, current: () -> Boolean): WebResourceResponse? {
        if (closed || !current()) return denied()
        val original = request.url.toString()
        if (request.url.scheme !in listOf("http", "https")) {
            return if (request.url.scheme in listOf("data", "blob", "about")) null else denied()
        }
        val uri = parse(original) ?: return denied()
        if (!sameOrigin(uri)) return null
        val mapped = normalized(original) ?: return denied()
        if (mapped.toString() == original) return null
        if (request.method !in listOf("GET", "HEAD")) return denied()
        if (connections.size >= 16) return denied(503)
        var connection: HttpURLConnection? = null
        try {
            var target = mapped
            for (attempt in 0..3) {
                if (closed || !current()) return denied()
                val opened = target.toURL().openConnection() as HttpURLConnection
                connection = opened; connections.add(opened)
                opened.instanceFollowRedirects = false
                opened.connectTimeout = 10000; opened.readTimeout = 15000
                opened.requestMethod = request.method
                request.requestHeaders.forEach { (name,value) ->
                    if (name.lowercase() !in setOf("host", "cookie", "connection", "content-length", "accept-encoding"))
                        opened.setRequestProperty(name, value)
                }
                opened.setRequestProperty("Accept-Encoding", "identity")
                cookies.getCookie(target.toString())?.let { opened.setRequestProperty("Cookie", it) }
                val status = opened.responseCode
                if (status in 300..399) {
                    val next = normalized(target.resolve(opened.getHeaderField("Location") ?: return denied(502)).toString()) ?: return denied(502)
                    opened.disconnect(); connections.remove(opened); connection = null
                    target = next
                    if (attempt == 3) return denied(502)
                    continue
                }
                if (status !in 200..599 || opened.contentLengthLong > 64L*1024*1024 || closed || !current()) return denied(502)
                val type = (opened.contentType ?: "application/octet-stream").substringBefore(';').trim()
                val headers = mutableMapOf<String,String>()
                opened.headerFields.forEach { (key,value) ->
                    if (key != null && value != null && key.lowercase() !in setOf("set-cookie", "transfer-encoding", "connection"))
                        headers[key] = value.joinToString(", ")
                }
                val input = if (request.method == "HEAD") ByteArrayInputStream(ByteArray(0))
                    else if (status >= 400) opened.errorStream ?: ByteArrayInputStream(ByteArray(0)) else opened.inputStream
                val source = object : InputStream() {
                    private var bytes = 0L
                    private val deadline = System.nanoTime() + 60L*1_000_000_000
                    private fun consumed(count: Int): Int {
                        if (count < 0) { close(); return -1 }
                        if (count > 0) bytes += count
                        if (bytes > 64L*1024*1024 || closed || !current() || System.nanoTime() > deadline) {
                            close(); throw IOException("Article resource retired")
                        }
                        return count
                    }
                    override fun read(): Int {
                        val value = input.read(); consumed(if (value < 0) -1 else 1); return value
                    }
                    override fun read(buffer: ByteArray, offset: Int, length: Int): Int = consumed(input.read(buffer, offset, length))
                    override fun close() { try { input.close() } finally { opened.disconnect(); connections.remove(opened) } }
                }
                connection = null
                return WebResourceResponse(type, "utf-8", status, opened.responseMessage ?: "Response", headers, source)
            }
            return denied(502)
        } catch (_: Exception) { return denied(502) }
        finally { connection?.let { it.disconnect(); connections.remove(it) } }
    }
    fun close() { closed = true; connections.toList().forEach { it.disconnect() }; connections.clear() }

    fun bootstrap(): String {
        val base = JSONObject.quote(server.toString())
        return """
(function(){
'use strict';
const base=new URL($base),prefix=base.pathname.replace(/\/+$/,''),origin=base.origin;
const roots=new Set(['static','api','upload-files','notes','blogs','manifest.json','sw.js','favicon.ico']);
function map(value){
 try{
  const url=new URL(String(value),location.href);
  if(url.origin!==origin||!prefix||url.pathname===prefix||url.pathname.startsWith(prefix+'/'))return url.href;
  if(roots.has(url.pathname.split('/')[1]))url.pathname=prefix+url.pathname;
  return url.href;
 }catch(_){return value;}
}
if(navigator.serviceWorker){navigator.serviceWorker.register=function(){return Promise.reject(new Error('Native article module owns offline state'));};}
const fetch=window.fetch;
window.fetch=function(input,init){
 if(input instanceof Request){
  const url=map(input.url);
  if(url===input.url)return fetch.call(this,input,init);
  let request=new Request(url,input);
  if(!request.body)return fetch.call(this,request,init);
  // A Request body exposes a ReadableStream; Chrome forbids streaming uploads
  // on HTTP/1. Materialize as a browser Blob to preserve bytes and compatibility.
  return request.blob().then(body=>fetch.call(this,new Request(request,{body}),init));
 }
 return fetch.call(this,map(input),init);
};
const open=XMLHttpRequest.prototype.open;
XMLHttpRequest.prototype.open=function(method,url){const args=Array.from(arguments);args[1]=map(url);return open.apply(this,args);};
for(const method of ['submit','requestSubmit']){
 const original=HTMLFormElement.prototype[method];
 if(original)HTMLFormElement.prototype[method]=function(){this.action=map(this.action);return original.apply(this,arguments);};
}
document.addEventListener('submit',event=>{const form=event.target;if(form instanceof HTMLFormElement)form.action=map(form.action);},true);
function style(){
 if(!document.head)return false;
 const sheet=document.createElement('style');
 sheet.textContent='body>header{display:none!important}#mainTabs [data-tab="notes"],#mainTabs [data-tab="tasks"]{display:none!important}:root{--color-primary:#0b57ee}';
 document.head.appendChild(sheet);return true;
}
if(!style()){const watch=new MutationObserver(()=>{if(style())watch.disconnect();});watch.observe(document,{childList:true,subtree:true});}
const blobs=new Map(),pendingBlobs=new Map();
const createObjectURL=URL.createObjectURL.bind(URL),revokeObjectURL=URL.revokeObjectURL.bind(URL);
URL.createObjectURL=function(blob){
 const url=createObjectURL(blob);
 if(blob instanceof Blob&&blob.size<=32*1024*1024&&blobs.size<32)blobs.set(url,blob);
 return url;
};
URL.revokeObjectURL=function(url){blobs.delete(String(url));return revokeObjectURL(url);};
function downloadAnchor(a){
 if(!a||!a.hasAttribute('download')||!a.href.startsWith('blob:'+origin+'/'))return false;
 if(pendingBlobs.size)return true;
 const url=a.href,known=blobs.get(url);
 const pending=known?Promise.resolve(known):fetch(url).then(r=>r.blob());
 pending.catch(()=>{});
 pendingBlobs.set(url,pending);
 setTimeout(()=>{if(pendingBlobs.get(url)===pending)pendingBlobs.delete(url);},65000);
 BookstarkArticleDownload.postMessage(JSON.stringify({kind:'download',url,name:a.download||'article-export'}));
 return true;
}
const anchorClick=HTMLAnchorElement.prototype.click;
HTMLAnchorElement.prototype.click=function(){
 if(!downloadAnchor(this))return anchorClick.apply(this,arguments);
};
document.addEventListener('click',function(event){
 const a=event.target&&event.target.closest?event.target.closest('a[download]'):null;
 if(downloadAnchor(a))event.preventDefault();
},true);
Object.defineProperty(window,'__bookstarkReadArticleBlob',{value:async function(id,url){
 try{
  const pending=pendingBlobs.get(url);pendingBlobs.delete(url);
  const blob=pending?await pending:await fetch(url).then(r=>r.blob());
  if(blob.size>32*1024*1024)throw Error('limit');
  const bytes=new Uint8Array(await blob.arrayBuffer());
  BookstarkArticleDownload.postMessage(JSON.stringify({kind:'start',id,total:bytes.length,mime:blob.type}));
  for(let offset=0,index=0;offset<bytes.length;offset+=32768,index++){
   const part=bytes.subarray(offset,offset+32768);let binary='';
   for(let i=0;i<part.length;i++)binary+=String.fromCharCode(part[i]);
   BookstarkArticleDownload.postMessage(JSON.stringify({kind:'chunk',id,index,data:btoa(binary)}));
  }
  BookstarkArticleDownload.postMessage(JSON.stringify({kind:'end',id}));
 }catch(_){BookstarkArticleDownload.postMessage(JSON.stringify({kind:'failed',id}));}
},writable:false,configurable:false});
})();
""".trimIndent()
    }
}
