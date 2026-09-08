package com.bookstark.app;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Gravity;
import android.view.ViewGroup;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;

public class MainActivity extends Activity {
    private static final String TAG = "BookStarkAndroid";
    private static final int PORT = 18089;

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private WebView webView;
    private TextView statusView;
    private Process backendProcess;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        buildView();
        startBackendAndLoad();
    }

    private void buildView() {
        FrameLayout root = new FrameLayout(this);
        webView = new WebView(this);
        statusView = new TextView(this);
        statusView.setText("BookStark 正在启动...");
        statusView.setTextSize(16);
        statusView.setGravity(Gravity.CENTER);

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setUseWideViewPort(true);
        settings.setLoadWithOverviewMode(false);
        settings.setTextZoom(100);
        settings.setSupportZoom(false);
        settings.setBuiltInZoomControls(false);
        settings.setDisplayZoomControls(false);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        webView.setInitialScale(100);
        webView.setWebViewClient(new WebViewClient());

        root.addView(webView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));
        root.addView(statusView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));
        setContentView(root);
    }

    private void startBackendAndLoad() {
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    File binary = prepareBackendBinary();
                    File db = new File(getFilesDir(), "bookstark.db");
                    File workDir = getFilesDir();
                    ProcessBuilder pb = new ProcessBuilder(
                            binary.getAbsolutePath(),
                            "-port", String.valueOf(PORT),
                            "-mode", "release",
                            "-db", db.getAbsolutePath(),
                            "-jwt-secret", "bookstark-android-local"
                    );
                    pb.directory(workDir);
                    pb.redirectErrorStream(true);
                    backendProcess = pb.start();
                    pipeLogs(backendProcess);
                    waitForBackend();
                    mainHandler.post(new Runnable() {
                        @Override
                        public void run() {
                            statusView.setVisibility(TextView.GONE);
                            webView.loadUrl("http://127.0.0.1:" + PORT + "/");
                        }
                    });
                } catch (final Exception e) {
                    Log.e(TAG, "Failed to start backend", e);
                    mainHandler.post(new Runnable() {
                        @Override
                        public void run() {
                            statusView.setText("BookStark 启动失败\n" + e.getMessage());
                        }
                    });
                }
            }
        }, "bookstark-backend").start();
    }

    private File prepareBackendBinary() throws IOException {
        File out = new File(getFilesDir(), "bookstark-arm64");
        if (!out.exists() || out.length() == 0) {
            InputStream in = getAssets().open("bookstark-arm64");
            try {
                FileOutputStream fos = new FileOutputStream(out);
                try {
                    byte[] buf = new byte[1024 * 64];
                    int n;
                    while ((n = in.read(buf)) > 0) {
                        fos.write(buf, 0, n);
                    }
                } finally {
                    fos.close();
                }
            } finally {
                in.close();
            }
        }
        if (!out.setExecutable(true, true)) {
            throw new IOException("无法设置后端可执行权限");
        }
        return out;
    }

    private void waitForBackend() throws Exception {
        long deadline = System.currentTimeMillis() + 30000;
        Exception last = null;
        while (System.currentTimeMillis() < deadline) {
            try {
                HttpURLConnection conn = (HttpURLConnection) new URL("http://127.0.0.1:" + PORT + "/").openConnection();
                conn.setConnectTimeout(1000);
                conn.setReadTimeout(1000);
                int code = conn.getResponseCode();
                conn.disconnect();
                if (code >= 200 && code < 500) return;
            } catch (Exception e) {
                last = e;
            }
            Thread.sleep(300);
        }
        throw new IOException("后端 30 秒内没有启动" + (last == null ? "" : ": " + last.getMessage()));
    }

    private void pipeLogs(final Process process) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
                    String line;
                    while ((line = reader.readLine()) != null) {
                        Log.i(TAG, line);
                    }
                } catch (IOException ignored) {
                }
            }
        }, "bookstark-log").start();
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) {
            webView.goBack();
            return;
        }
        super.onBackPressed();
    }

    @Override
    protected void onDestroy() {
        if (backendProcess != null) {
            backendProcess.destroy();
            backendProcess = null;
        }
        if (webView != null) {
            webView.destroy();
            webView = null;
        }
        super.onDestroy();
    }
}
