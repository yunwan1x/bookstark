package com.wails.app;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.app.DownloadManager;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Environment;
import android.os.Build;
import android.print.PrintManager;
import android.util.Base64;
import android.util.Log;
import android.webkit.CookieManager;
import androidx.webkit.WebViewCompat;
import androidx.webkit.WebViewFeature;
import android.webkit.JsResult;
import android.webkit.PermissionRequest;
import android.webkit.URLUtil;
import android.webkit.WebChromeClient;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import org.json.JSONObject;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.net.URI;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URISyntaxException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

/** Explicit, bounded browser capabilities. Never exposes the general Wails runtime. */
public final class BookStarkLinkBridge {
    private static final int MEDIA_PERMISSION = 29101, SAVE_DOCUMENT = 29102;
    private static final long MAX_BYTES = 100L * 1024 * 1024;
    private final Activity activity;
    private final WebView webView;
    private final Map<String, Transfer> transfers = new HashMap<>();
    private PermissionRequest mediaRequest;
    private Transfer pendingSave;
    private String pendingSaveID;
    private String navigationToken;
    private Runnable navigation;
    private WebView printView;
    private String workspaceOrigin;
    private String workspaceStartURL;

    private static class Transfer {
        File file;
        String name, mime, kind;
        long size;
        FileOutputStream output;
        void close() { try { if (output != null) output.close(); } catch (Exception ignored) {} output = null; }
        void delete() { close(); if (file != null) file.delete(); }
    }

    public BookStarkLinkBridge(Activity activity, WebView webView) {
        this.activity = activity;
        this.webView = webView;
    }
    // Unlike addJavascriptInterface, the listener carries an authenticated
    // frame identity. Subframes cannot forge a host/native capability request.
    public void installBridge() {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) return;
        WebViewCompat.addWebMessageListener(webView,"BookStarkNative",java.util.Collections.singleton("*"),
            (view,message,sourceOrigin,isMainFrame,replyProxy) -> {
                if (!isMainFrame || !sameOrigin(sourceOrigin.toString())) return;
                request(message.getData());
            });
    }
    public void trackWorkspace(String address) {
        try {
            URI uri=new URI(address);
            if ("http".equals(uri.getScheme()) && "127.0.0.1".equals(uri.getHost()) && uri.getPath().startsWith("/__bookstark/open/")) {
                workspaceOrigin="http://"+uri.getAuthority();
                workspaceStartURL=workspaceOrigin+uri.getPath()+"?choose=1";
            }
        } catch(Exception ignored) {}
    }
    public void chooseWorkspace() {
        if (workspaceStartURL != null) navigate(() -> webView.loadUrl(workspaceStartURL));
    }
    private static String originOf(String address) throws Exception {
        URI uri=new URI(address);
        if (!("http".equals(uri.getScheme()) || "https".equals(uri.getScheme())) || uri.getHost()==null) throw new Exception("Invalid workspace");
        return uri.getScheme()+"://"+uri.getAuthority();
    }
    private void clientRequest(String id, JSONObject args) throws Exception {
        final String expected=originOf(webView.getUrl());
        if (workspaceOrigin==null || !expected.equals(args.optString("origin"))) throw new Exception("Untrusted workspace");
        final String endpoint=workspaceOrigin+"/__bookstark/client";
        final String cookies=CookieManager.getInstance().getCookie(workspaceOrigin);
        final byte[] body=args.toString().getBytes(StandardCharsets.UTF_8);
        new Thread(() -> {
            Object result=null;String error=null;
            HttpURLConnection connection=null;
            try {
                connection=(HttpURLConnection)new URL(endpoint).openConnection();
                connection.setConnectTimeout(5000);connection.setReadTimeout(5000);
                connection.setRequestMethod("POST");connection.setDoOutput(true);
                connection.setRequestProperty("Content-Type","application/json");
                if(cookies!=null)connection.setRequestProperty("Cookie",cookies);
                try(OutputStream out=connection.getOutputStream()){out.write(body);}
                if(connection.getResponseCode()!=200)throw new Exception("Client settings request failed");
                java.io.ByteArrayOutputStream buffer=new java.io.ByteArrayOutputStream();
                try(java.io.InputStream input=connection.getInputStream()) {
                    byte[] chunk=new byte[4096];int size;
                    while((size=input.read(chunk))!=-1){if(buffer.size()+size>16384)throw new Exception("Client response too large");buffer.write(chunk,0,size);}
                }
                byte[] bytes=buffer.toByteArray();
                result=new org.json.JSONTokener(new String(bytes,StandardCharsets.UTF_8)).nextValue();
            }catch(Exception e){error="Client settings request failed";}finally{if(connection!=null)connection.disconnect();}
            final Object value=result;final String failure=error;
            activity.runOnUiThread(() -> {try{if(expected.equals(originOf(webView.getUrl()))) { if(failure==null && "switch".equals(args.optString("operation"))) chooseWorkspace(); else if(failure==null && "tools-open".equals(args.optString("operation"))) navigate(() -> webView.loadUrl(workspaceStartURL.replace("?choose=1","?tools=1"))); else reply(id,value,failure); }}catch(Exception ignored){}});
        }).start();
    }
    private String text(String zh, String en) { return Locale.getDefault().getLanguage().equals("zh") ? zh : en; }
    static boolean isWebAddress(String address) {
        if (address == null || address.length() > 16384) return false;
        try {
            URI uri = new URI(address);
            return ("https".equals(uri.getScheme()) || "http".equals(uri.getScheme()))
                && uri.getHost() != null && uri.getUserInfo() == null;
        } catch (URISyntaxException error) { return false; }
    }
    private void openExternal(String address) {
        if (!isWebAddress(address)) return;
        activity.runOnUiThread(() -> {
            try { activity.startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(address))); }
            catch (Exception error) { Log.w("BookStark", "Could not open external web link", error); }
        });
    }
    private void reply(String id, Object value, String error) {
        String script = "window.BookStarkHostReply && window.BookStarkHostReply(" + JSONObject.quote(id) + "," +
            (value == null || value == JSONObject.NULL ? "null" : value instanceof String ? JSONObject.quote((String) value) : String.valueOf(value)) + "," + (error == null ? "null" : JSONObject.quote(error)) + ")";
        activity.runOnUiThread(() -> webView.evaluateJavascript(script, null));
    }
    private void request(String json) {
        if (json == null || json.length() > 300000) return;
        activity.runOnUiThread(() -> {
            String id = "";
            try {
                JSONObject request = new JSONObject(json);
                id = request.getString("id");
                if (!id.matches("[a-zA-Z0-9_-]{1,100}")) return;
                String action = request.getString("action");
                JSONObject args = request.optJSONObject("args");
                if (args == null) args = new JSONObject();
                switch (action) {
                    case "client": clientRequest(id,args); break;
                    case "open-external": openExternal(args.getString("url")); break;
                    case "finish-navigation": finishNavigation(args.getString("token"),args.optBoolean("allowed")); break;
                    case "clipboard-write":
                        ((ClipboardManager) activity.getSystemService(Context.CLIPBOARD_SERVICE))
                            .setPrimaryClip(ClipData.newPlainText("BookStark", args.getString("text")));
                        reply(id, true, null); break;
                    case "save-begin": {
                        if (transfers.size() >= 3) throw new Exception("Too many pending exports");
                        Transfer transfer = new Transfer();
                        transfer.name = args.optString("name", "BookStark.txt").replaceAll("[\\\\/\\p{Cntrl}]", "_");
                        if (transfer.name.length() > 160) transfer.name = transfer.name.substring(0, 160);
                        transfer.mime = args.optString("mime", "application/octet-stream");
                        transfer.kind = args.optString("kind", "save");
                        transfer.file = File.createTempFile("bookstark-export-", ".tmp", activity.getCacheDir());
                        transfer.output = new FileOutputStream(transfer.file);
                        String token = UUID.randomUUID().toString(); transfers.put(token, transfer);
                        reply(id, token, null); break;
                    }
                    case "save-chunk": {
                        String token = args.getString("token"); Transfer transfer = transfers.get(token);
                        if (transfer == null || transfer.output == null) throw new Exception("Export has expired");
                        byte[] bytes = Base64.decode(args.getString("data"), Base64.DEFAULT);
                        if (bytes.length > 196608 || transfer.size + bytes.length > MAX_BYTES) {
                            transfers.remove(token); transfer.delete(); throw new Exception("Export exceeds 100 MB");
                        }
                        transfer.output.write(bytes); transfer.size += bytes.length; reply(id, true, null); break;
                    }
                    case "save-cancel": {
                        Transfer transfer = transfers.remove(args.getString("token"));
                        if (transfer != null) transfer.delete(); reply(id, true, null); break;
                    }
                    case "save-finish": {
                        String token = args.getString("token"); Transfer transfer = transfers.get(token);
                        if (transfer == null) throw new Exception("Export has expired");
                        if (pendingSave != null) throw new Exception("Finish the previous save dialog first");
                        transfers.remove(token); transfer.close();
                        if ("print".equals(transfer.kind)) {
                            print(transfer); reply(id, true, null); break;
                        }
                        pendingSave = transfer; pendingSaveID = id;
                        try {
                            Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                                .setType(transfer.mime).putExtra(Intent.EXTRA_TITLE, transfer.name);
                            activity.startActivityForResult(intent, SAVE_DOCUMENT);
                        } catch (Exception error) { pendingSave = null; pendingSaveID = null; transfer.delete(); throw error; }
                        break;
                    }
                    default: throw new Exception("Unsupported native action");
                }
            } catch (Exception error) { reply(id, null, error.getMessage()); }
        });
    }
    public boolean activityResult(int code, int result, Intent data) {
        if (code != SAVE_DOCUMENT) return false;
        final Transfer transfer = pendingSave; final String id = pendingSaveID;
        pendingSave = null; pendingSaveID = null;
        if (transfer == null) return true;
        if (result != Activity.RESULT_OK || data == null || data.getData() == null) {
            transfer.delete(); reply(id, false, null); return true;
        }
        final Uri uri = data.getData();
        new Thread(() -> {
            try (FileInputStream input = new FileInputStream(transfer.file);
                 OutputStream output = activity.getContentResolver().openOutputStream(uri, "wt")) {
                if (output == null) throw new Exception("Cannot open selected file");
                byte[] buffer = new byte[65536]; int count;
                while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
                output.flush(); reply(id, true, null);
            } catch (Exception error) { reply(id, null, error.getMessage()); }
            finally { transfer.delete(); }
        }, "BookStark-save").start();
        return true;
    }
    public void download(String url, String agent, String disposition, String mime, long size) {
        if (url.startsWith("blob:") || url.startsWith("data:") || sameOrigin(url)) {
            webView.evaluateJavascript("window.BookStarkHost && window.BookStarkHost.downloadURL(" + JSONObject.quote(url) + "," +
                JSONObject.quote(URLUtil.guessFileName(url, disposition, mime)) + ")", null);
            return;
        }
        if (!isWebAddress(url)) return;
        try {
            DownloadManager.Request request = new DownloadManager.Request(Uri.parse(url));
            String cookies = CookieManager.getInstance().getCookie(url);
            if (cookies != null) request.addRequestHeader("Cookie", cookies);
            if (agent != null) request.addRequestHeader("User-Agent", agent);
            if (mime != null) request.setMimeType(mime);
            request.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
            request.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, URLUtil.guessFileName(url, disposition, mime));
            ((DownloadManager) activity.getSystemService(Context.DOWNLOAD_SERVICE)).enqueue(request);
        } catch (Exception error) { new AlertDialog.Builder(activity).setMessage(text("下载失败：", "Download failed: ") + error.getMessage()).setPositiveButton(android.R.string.ok, null).show(); }
    }
    private boolean sameOrigin(String address) {
        try {
            URI requested = new URI(address), current = new URI(webView.getUrl());
            return requested.getScheme().equals(current.getScheme()) && requested.getHost().equals(current.getHost())
                && (requested.getPort() < 0 ? ("https".equals(requested.getScheme()) ? 443 : 80) : requested.getPort())
                 == (current.getPort() < 0 ? ("https".equals(current.getScheme()) ? 443 : 80) : current.getPort());
        } catch (Exception ignored) { return false; }
    }
    private boolean allowedMediaOrigin(String address) {
        if (sameOrigin(address)) return true;
        try {
            URI requested=new URI(address),current=new URI(webView.getUrl());
            return "http".equals(current.getScheme()) && "127.0.0.1".equals(current.getHost())
                && "http".equals(requested.getScheme()) && requested.getHost().matches("tool-[a-f0-9]{32}\\.localhost")
                && requested.getPort()==current.getPort() && current.getPath().startsWith("/tools/run/");
        } catch(Exception ignored) { return false; }
    }
    public void media(PermissionRequest request) {
        activity.runOnUiThread(() -> {
            if (!allowedMediaOrigin(request.getOrigin().toString()) || mediaRequest != null) { request.deny(); return; }
            for (String resource : request.getResources())
                if (!resource.equals(PermissionRequest.RESOURCE_VIDEO_CAPTURE) && !resource.equals(PermissionRequest.RESOURCE_AUDIO_CAPTURE)) { request.deny(); return; }
            mediaRequest = request;
            new AlertDialog.Builder(activity).setTitle(text("网页音视频权限", "Website media permission"))
                .setMessage(request.getOrigin() + "\n" + text("是否允许此网页使用摄像头或麦克风？", "Allow this website to use the camera or microphone?"))
                .setNegativeButton(android.R.string.cancel, (dialog, which) -> denyMedia())
                .setOnCancelListener(dialog -> denyMedia())
                .setPositiveButton(android.R.string.ok, (dialog, which) -> {
                    if (mediaRequest != request) return;
                    ArrayList<String> missing = new ArrayList<>();
                    for (String resource : request.getResources()) {
                        String permission = resource.equals(PermissionRequest.RESOURCE_VIDEO_CAPTURE) ? Manifest.permission.CAMERA : Manifest.permission.RECORD_AUDIO;
                        if (!hasPermission(permission)) missing.add(permission);
                    }
                    if (missing.isEmpty()) grantMedia();
                    else activity.requestPermissions(missing.toArray(new String[0]), MEDIA_PERMISSION);
                }).show();
        });
    }
    private boolean hasPermission(String permission) { return Build.VERSION.SDK_INT < 23 || activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED; }
    private void denyMedia() { if (mediaRequest != null) mediaRequest.deny(); mediaRequest = null; }
    public void cancelMedia(PermissionRequest request) { if (mediaRequest == request) mediaRequest = null; }
    private void grantMedia() {
        if (mediaRequest == null) return;
        PermissionRequest request = mediaRequest; mediaRequest = null;
        if (!allowedMediaOrigin(request.getOrigin().toString())) { request.deny(); return; }
        ArrayList<String> granted = new ArrayList<>();
        for (String resource : request.getResources()) {
            String permission = resource.equals(PermissionRequest.RESOURCE_VIDEO_CAPTURE) ? Manifest.permission.CAMERA : Manifest.permission.RECORD_AUDIO;
            if (hasPermission(permission)) granted.add(resource);
        }
        if (granted.isEmpty()) request.deny(); else request.grant(granted.toArray(new String[0]));
    }
    public boolean permissionResult(int code) { if (code != MEDIA_PERMISSION) return false; grantMedia(); return true; }
    public void navigate(Runnable action) {
        if (navigation != null) return;
        navigation = action; navigationToken = UUID.randomUUID().toString();
        String token = navigationToken;
        webView.evaluateJavascript("(async function(){let ok=false;try{ok=typeof window.BookStarkBeforeLeave==='function'?await window.BookStarkBeforeLeave():true;}catch(e){} BookStarkNative.postMessage(JSON.stringify({id:'navigation',action:'finish-navigation',args:{token:" + JSONObject.quote(token) + ",allowed:!!ok}}))})()", null);
    }
    private void finishNavigation(String token, boolean allowed) {
        activity.runOnUiThread(() -> {
            if (navigationToken == null || !navigationToken.equals(token)) return;
            Runnable action = navigation; navigation = null; navigationToken = null;
            if (allowed && action != null) action.run();
        });
    }
    private void print(Transfer transfer) throws Exception {
        byte[] bytes = new byte[(int) transfer.size];
        try (FileInputStream stream = new FileInputStream(transfer.file)) {
            int offset = 0, count; while (offset < bytes.length && (count = stream.read(bytes, offset, bytes.length-offset)) != -1) offset += count;
        } finally { transfer.delete(); }
        if (printView != null) printView.destroy();
        printView = new WebView(activity);
        WebView view = printView;
        view.getSettings().setJavaScriptEnabled(false);
        view.getSettings().setAllowFileAccess(false);
        view.getSettings().setAllowContentAccess(false);
        view.setWebViewClient(new WebViewClient() {
            @Override public void onPageFinished(WebView finished, String url) {
                PrintManager manager = (PrintManager) activity.getSystemService(Context.PRINT_SERVICE);
                manager.print(transfer.name, finished.createPrintDocumentAdapter(transfer.name), null);
            }
        });
        view.loadDataWithBaseURL(webView.getUrl(), new String(bytes, StandardCharsets.UTF_8), "text/html", "UTF-8", null);
    }
    public void destroy() {
        denyMedia(); for (Transfer transfer : transfers.values()) transfer.delete(); transfers.clear();
        if (pendingSave != null) pendingSave.delete(); pendingSave = null;
        if (printView != null) printView.destroy(); printView = null;
    }
    public static class ChromeClient extends WebChromeClient {
        private final Activity activity; private final BookStarkLinkBridge host;
        public ChromeClient(Activity activity, BookStarkLinkBridge host) { this.activity = activity; this.host = host; }
        @Override public void onPermissionRequest(PermissionRequest request) { host.media(request); }
        @Override public void onPermissionRequestCanceled(PermissionRequest request) { host.cancelMedia(request); }
        @Override public boolean onJsAlert(WebView view, String url, String message, JsResult result) {
            new AlertDialog.Builder(activity).setMessage(message).setPositiveButton(android.R.string.ok, (d,w) -> result.confirm()).setOnCancelListener(d -> result.cancel()).show(); return true;
        }
        @Override public boolean onJsConfirm(WebView view, String url, String message, JsResult result) {
            new AlertDialog.Builder(activity).setMessage(message).setPositiveButton(android.R.string.ok, (d,w) -> result.confirm()).setNegativeButton(android.R.string.cancel, (d,w) -> result.cancel()).setOnCancelListener(d -> result.cancel()).show(); return true;
        }
        @Override public boolean onJsBeforeUnload(WebView view, String url, String message, JsResult result) { return onJsConfirm(view,url,message,result); }
    }
}
