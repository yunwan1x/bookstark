package com.bookstark.bookstark_flutter

import android.content.Intent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    private var assetSecureWindow: AssetSecureWindowChannel? = null
    private var fileExport: FileExportChannel? = null
    private var complexSourceIo: ComplexSourceIoChannel? = null
    private var articleSession: ArticleWebSessionChannel? = null
    private var htmlPreview: HtmlPreviewSessionChannel? = null
    private var recoveryStorage: RecoveryStorageChannel? = null
    private var complexRecovery: ComplexRecoveryChannel? = null
    private var backupPicker: LocalBackupPickerChannel? = null
    private var ownedImagePicker: OwnedImagePickerChannel? = null
    private var articleAttachmentPicker: LocalArticleAttachmentPickerChannel? = null
    private var localDataControl: LocalDataControlChannel? = null
    private var localContentCrypto: LocalContentCryptoChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "bookstark/local_html_preview",
            LocalHtmlPreviewFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "bookstark/public_html_preview",
            PublicHtmlPreviewFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "bookstark/owned15_generation_view",
            Owned15GenerationFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "bookstark/owned_complex_view",
            OwnedComplexFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "bookstark/complex_editor_view",
            ComplexEditorFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "bookstark/local_richdoc_view",
            LocalRichdocFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "bookstark/local_mindmap_view",
            LocalMindmapFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "bookstark/local_drawing_view",
            LocalDrawingFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "bookstark/local_presentation_view",
            LocalPresentationFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "bookstark/local_markdown_view",
            LocalMarkdownFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "bookstark/shared_complex_view", SharedComplexFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "bookstark/shared_markdown_view",
            SharedMarkdownFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "bookstark/public_complex_readonly_view",
            PublicComplexReadOnlyFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "bookstark/public_markdown_view",
            PublicMarkdownFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "bookstark/admin_terminal", AdminTerminalFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "bookstark/admin_file_editor", AdminFileEditorFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "bookstark/article_web_view", ArticleWebFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        articleSession?.dispose()
        articleSession = ArticleWebSessionChannel(flutterEngine.dartExecutor.binaryMessenger)
        assetSecureWindow?.dispose()
        assetSecureWindow = AssetSecureWindowChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        fileExport?.dispose()
        fileExport = FileExportChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        complexSourceIo?.dispose()
        complexSourceIo = ComplexSourceIoChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        htmlPreview?.dispose()
        htmlPreview = HtmlPreviewSessionChannel(flutterEngine.dartExecutor.binaryMessenger)
        recoveryStorage?.dispose()
        recoveryStorage = RecoveryStorageChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        complexRecovery?.dispose()
        complexRecovery = ComplexRecoveryChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        backupPicker?.dispose()
        backupPicker = LocalBackupPickerChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        articleAttachmentPicker?.dispose()
        articleAttachmentPicker = LocalArticleAttachmentPickerChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        ownedImagePicker?.dispose()
        ownedImagePicker = OwnedImagePickerChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        localDataControl?.dispose()
        localDataControl = LocalDataControlChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        localContentCrypto?.dispose()
        localContentCrypto = LocalContentCryptoChannel(flutterEngine.dartExecutor.binaryMessenger)
    }

    @Deprecated("Android activity result compatibility bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (ownedImagePicker?.onActivityResult(requestCode, resultCode, data) != true &&
            complexSourceIo?.onActivityResult(requestCode, resultCode, data) != true &&
            fileExport?.onActivityResult(requestCode, resultCode, data) != true &&
            backupPicker?.onActivityResult(requestCode, resultCode, data) != true &&
            articleAttachmentPicker?.onActivityResult(requestCode, resultCode, data) != true &&
            !ArticleWebView.onActivityResult(requestCode, resultCode, data)) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onStop() {
        ownedImagePicker?.onHostStopped()
        complexSourceIo?.onHostStopped()
        ArticleWebView.pauseAll()
        localContentCrypto?.retire()
        AdminTerminalView.retireAll()
        AdminFileEditorView.retireAll()
        super.onStop()
    }

    override fun onDestroy() {
        ownedImagePicker?.dispose()
        ownedImagePicker = null
        complexSourceIo?.dispose()
        complexSourceIo = null
        articleSession?.dispose()
        articleSession = null
        localContentCrypto?.dispose()
        localContentCrypto = null
        AdminTerminalView.retireAll()
        AdminFileEditorView.retireAll()
        assetSecureWindow?.dispose()
        assetSecureWindow = null
        fileExport?.dispose()
        fileExport = null
        htmlPreview?.dispose()
        htmlPreview = null
        recoveryStorage?.dispose()
        recoveryStorage = null
        complexRecovery?.dispose()
        complexRecovery = null
        localDataControl?.dispose()
        localDataControl = null
        backupPicker?.dispose()
        backupPicker = null
        articleAttachmentPicker?.dispose()
        articleAttachmentPicker = null
        super.onDestroy()
    }
}
