var ImagesPage = (function() {
    'use strict';

    var IMAGES_KEY = 'images-view-mode';
    var PAGE_SIZE = 20;

    var currentPage = 1;
    var totalPages = 1;
    var currentData = [];
    var currentView = localStorage.getItem(IMAGES_KEY) || 'grid';
    var searchTimer = null;
    var totalItems = 0;
    var totalSize = 0;

    // Selection state
    var selectMode = false;
    var selectedIds = {};

    // === Init ===
    function init() {
        setViewMode(currentView);

        document.getElementById('img-search').addEventListener('input', function() {
            clearTimeout(searchTimer);
            searchTimer = setTimeout(function() {
                currentPage = 1;
                loadImages(1);
            }, 300);
        });

        document.getElementById('view-grid').addEventListener('click', function() {
            toggleView('grid');
        });
        document.getElementById('view-list').addEventListener('click', function() {
            toggleView('list');
        });

        document.getElementById('btn-upload').addEventListener('click', function() {
            document.getElementById('img-file-input').click();
        });

        document.getElementById('img-file-input').addEventListener('change', function(e) {
            if (e.target.files && e.target.files.length > 0) {
                uploadFiles(e.target.files);
                e.target.value = '';
            }
        });

        // Select mode
        document.getElementById('btn-select-mode').addEventListener('click', function() {
            toggleSelectMode();
        });
        document.getElementById('btn-select-all').addEventListener('click', function() {
            selectAll();
        });
        document.getElementById('btn-batch-del').addEventListener('click', function() {
            batchDelete();
        });
        document.getElementById('btn-cancel-select').addEventListener('click', function() {
            exitSelectMode();
        });

        // Drag & drop
        var content = document.getElementById('images-content');
        var dragCounter = 0;
        content.addEventListener('dragenter', function(e) {
            e.preventDefault();
            dragCounter++;
            content.classList.add('drag-over');
        });
        content.addEventListener('dragover', function(e) {
            e.preventDefault();
        });
        content.addEventListener('dragleave', function(e) {
            e.preventDefault();
            dragCounter--;
            if (dragCounter <= 0) {
                dragCounter = 0;
                content.classList.remove('drag-over');
            }
        });
        content.addEventListener('drop', function(e) {
            e.preventDefault();
            dragCounter = 0;
            content.classList.remove('drag-over');
            if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
                uploadFiles(e.dataTransfer.files);
            }
        });

        loadImages(1);
    }

    // === Select mode ===
    function toggleSelectMode() {
        if (selectMode) {
            exitSelectMode();
        } else {
            enterSelectMode();
        }
    }

    function enterSelectMode() {
        selectMode = true;
        selectedIds = {};
        var content = document.getElementById('images-content');
        content.classList.add('select-mode');
        document.getElementById('btn-select-mode').classList.add('active');
        document.getElementById('select-bar').classList.add('visible');
        updateSelectUI();
    }

    function exitSelectMode() {
        selectMode = false;
        selectedIds = {};
        var content = document.getElementById('images-content');
        content.classList.remove('select-mode');
        document.getElementById('btn-select-mode').classList.remove('active');
        document.getElementById('select-bar').classList.remove('visible');
        // Remove selected class from all items
        var items = content.querySelectorAll('.selected');
        for (var i = 0; i < items.length; i++) {
            items[i].classList.remove('selected');
        }
        var checks = content.querySelectorAll('.checked');
        for (var j = 0; j < checks.length; j++) {
            checks[j].classList.remove('checked');
            checks[j].innerHTML = '';
        }
    }

    function toggleSelect(id) {
        if (selectedIds[id]) {
            delete selectedIds[id];
        } else {
            selectedIds[id] = true;
        }
        updateItemSelectState(id);
        updateSelectUI();
    }

    function selectAll() {
        var allSelected = true;
        for (var i = 0; i < currentData.length; i++) {
            if (!selectedIds[currentData[i].id]) {
                allSelected = false;
                break;
            }
        }
        if (allSelected) {
            // Deselect all
            for (var j = 0; j < currentData.length; j++) {
                delete selectedIds[currentData[j].id];
                updateItemSelectState(currentData[j].id);
            }
        } else {
            // Select all
            for (var k = 0; k < currentData.length; k++) {
                selectedIds[currentData[k].id] = true;
                updateItemSelectState(currentData[k].id);
            }
        }
        updateSelectUI();
    }

    function updateItemSelectState(id) {
        var isSelected = !!selectedIds[id];
        // Grid card
        var card = document.querySelector('.img-card[data-id="' + id + '"]');
        if (card) {
            card.classList.toggle('selected', isSelected);
            var check = card.querySelector('.img-card-check');
            if (check) {
                check.classList.toggle('checked', isSelected);
                check.innerHTML = isSelected ? '<i class="fa-solid fa-check" style="font-size:10px"></i>' : '';
            }
        }
        // List row
        var row = document.querySelector('.img-row[data-id="' + id + '"]');
        if (row) {
            row.classList.toggle('selected', isSelected);
            var rowCheck = row.querySelector('.img-row-check');
            if (rowCheck) {
                rowCheck.classList.toggle('checked', isSelected);
                rowCheck.innerHTML = isSelected ? '<i class="fa-solid fa-check" style="font-size:10px"></i>' : '';
            }
        }
    }

    function updateSelectUI() {
        var count = Object.keys(selectedIds).length;
        document.getElementById('select-count').textContent = count;
        document.getElementById('btn-batch-del').disabled = count === 0;
        var allSelected = currentData.length > 0 && count === currentData.length;
        document.getElementById('btn-select-all').textContent = allSelected ? '取消全选' : '全选';
    }

    function batchDelete() {
        var ids = Object.keys(selectedIds);
        if (ids.length === 0) return;
        BSDialog.confirm2('确定删除选中的 ' + ids.length + ' 张图片？').then(function(ok) {
            if (!ok) return;
            var deleted = 0;
            var failed = 0;
            ids.forEach(function(id) {
                csrfFetch('/api/uploads/' + id, { method: 'DELETE' })
                    .then(function(r) { return r.json(); })
                    .then(function(res) {
                        if (res.code !== 0) { failed++; } else { deleted++; }
                        if (deleted + failed === ids.length) {
                            if (deleted > 0) BSDialog.toast('已删除 ' + deleted + ' 张图片', 'success');
                            if (failed > 0) BSDialog.toast(failed + ' 张删除失败', 'error');
                            exitSelectMode();
                            loadImages(currentPage);
                        }
                    })
                    .catch(function() {
                        failed++;
                        if (deleted + failed === ids.length) {
                            if (deleted > 0) BSDialog.toast('已删除 ' + deleted + ' 张图片', 'success');
                            if (failed > 0) BSDialog.toast(failed + ' 张删除失败', 'error');
                            exitSelectMode();
                            loadImages(currentPage);
                        }
                    });
            });
        });
    }

    // === Load images ===
    function loadImages(page) {
        currentPage = page;
        var keyword = (document.getElementById('img-search').value || '').trim();
        var params = 'page=' + page + '&page_size=' + PAGE_SIZE;
        if (keyword) params += '&keyword=' + encodeURIComponent(keyword);

        renderLoadingSkeleton();

        csrfFetch('/api/uploads?' + params)
            .then(function(r) { return r.json(); })
            .then(function(res) {
                currentData = res.data || [];
                totalItems = res.total || 0;
                totalPages = res.total_pages || 1;
                totalSize = 0;
                for (var i = 0; i < currentData.length; i++) {
                    totalSize += currentData[i].file_size || 0;
                }
                updateStats(res.total || 0, res.total_size || 0);
                // Exit select mode on reload
                if (selectMode) exitSelectMode();
                renderCurrentView();
                renderPagination('img-pagination', currentPage, totalPages, function(p) {
                    loadImages(p);
                }, { showCount: true, totalItems: totalItems });
            })
            .catch(function(err) {
                console.error('Failed to load images', err);
                BSDialog.toast('加载图片失败', 'error');
                renderCurrentView();
            });
    }

    function renderLoadingSkeleton() {
        var listEl = document.getElementById('img-list');
        var emptyEl = document.getElementById('img-empty');
        var paginationEl = document.getElementById('img-pagination');
        if (!listEl) return;
        if (emptyEl) emptyEl.style.display = 'none';
        if (paginationEl) paginationEl.innerHTML = '';
        listEl.style.display = '';
        listEl.innerHTML = currentView === 'list' ? buildListSkeleton() : buildGridSkeleton();
    }

    function buildGridSkeleton() {
        var html = '<div class="images-grid images-skeleton" aria-hidden="true">';
        for (var i = 0; i < 8; i++) {
            var titleWidth = [72, 54, 64, 46, 78, 58, 68, 50][i] || 62;
            var metaWidth = [48, 36, 42, 56, 44, 38, 52, 34][i] || 44;
            html += '<div class="images-skeleton-card">';
            html += '<div class="images-skeleton-block images-skeleton-thumb"></div>';
            html += '<div class="images-skeleton-info">';
            html += '<div class="images-skeleton-block images-skeleton-title" style="width:' + titleWidth + '%"></div>';
            html += '<div class="images-skeleton-block images-skeleton-meta" style="width:' + metaWidth + '%"></div>';
            html += '</div></div>';
        }
        html += '</div>';
        return html;
    }

    function buildListSkeleton() {
        var html = '<div class="images-skeleton images-skeleton-list" aria-hidden="true">';
        for (var i = 0; i < 7; i++) {
            var nameWidth = [62, 48, 68, 54, 58, 44, 72][i] || 56;
            html += '<div class="images-skeleton-row">';
            html += '<div class="images-skeleton-block images-skeleton-row-thumb"></div>';
            html += '<div class="images-skeleton-block images-skeleton-row-name" style="max-width:' + nameWidth + '%"></div>';
            html += '<div class="images-skeleton-block images-skeleton-row-dim"></div>';
            html += '<div class="images-skeleton-block images-skeleton-row-dim"></div>';
            html += '<div class="images-skeleton-block images-skeleton-row-url"></div>';
            html += '<div class="images-skeleton-block images-skeleton-row-action"></div>';
            html += '</div>';
        }
        html += '</div>';
        return html;
    }

    // === Update stats ===
    function updateStats(count, size) {
        var el = document.getElementById('img-stats');
        if (!el) return;
        el.textContent = '共 ' + count + ' 张 · ' + formatFileSize(size || 0);
    }

    // === Render ===
    function renderCurrentView() {
        var listEl = document.getElementById('img-list');
        var emptyEl = document.getElementById('img-empty');

        if (!currentData || currentData.length === 0) {
            listEl.innerHTML = '';
            listEl.style.display = 'none';
            emptyEl.style.display = '';
            return;
        }

        emptyEl.style.display = 'none';
        listEl.style.display = '';

        if (currentView === 'grid') {
            renderGridView(currentData);
        } else {
            renderListView(currentData);
        }
    }

    // === Grid View ===
    function renderGridView(data) {
        var listEl = document.getElementById('img-list');
        var html = '<div class="images-grid">';
        for (var i = 0; i < data.length; i++) {
            var img = data[i];
            var thumbUrl = img.thumb_url || img.url;
            var fullUrl = img.url;
            var dims = (img.width && img.height) ? img.width + ' x ' + img.height : '';
            var sel = selectMode && selectedIds[img.id];
            html += '<div class="img-card' + (sel ? ' selected' : '') + '" data-id="' + img.id + '">';
            html += '<div class="img-card-check' + (sel ? ' checked' : '') + '" onclick="event.stopPropagation();ImagesPage.toggleSelect(' + img.id + ')">' + (sel ? '<i class="fa-solid fa-check" style="font-size:10px"></i>' : '') + '</div>';
            html += '<div class="img-card-thumb" onclick="' + (selectMode ? 'ImagesPage.toggleSelect(' + img.id + ')' : 'ImagesPage.preview(' + img.id + ')') + '"><img src="' + escAttr(thumbUrl) + '" alt="' + escAttr(img.file_name) + '" loading="lazy"></div>';
            html += '<div class="img-card-info">';
            html += '<div class="img-card-name" title="' + escAttr(img.file_name) + '">' + escHtml(img.file_name) + '</div>';
            html += '<div class="img-card-meta">';
            if (dims) html += dims + ' · ';
            html += formatFileSize(img.file_size);
            html += '</div>';
            html += '</div>';
            html += '</div>';
        }
        html += '</div>';
        listEl.innerHTML = html;
    }

    // === List View ===
    function renderListView(data) {
        var listEl = document.getElementById('img-list');
        var html = '';
        // Header
        html += '<div class="images-list-header">';
        html += '<div class="col-check"></div>';
        html += '<div class="col-thumb"></div>';
        html += '<div class="col-name">文件名</div>';
        html += '<div class="col-dims">尺寸</div>';
        html += '<div class="col-size">大小</div>';
        html += '<div class="col-date">日期</div>';
        html += '<div class="col-url">链接</div>';
        html += '<div class="col-actions">操作</div>';
        html += '</div>';
        html += '<div class="images-list">';
        for (var i = 0; i < data.length; i++) {
            var img = data[i];
            var thumbUrl = img.thumb_url || img.url;
            var fullUrl = img.url;
            var dims = (img.width && img.height) ? img.width + ' x ' + img.height : '-';
            var dateStr = formatDate(img.create_time);
            var sel = selectMode && selectedIds[img.id];
            html += '<div class="img-row' + (sel ? ' selected' : '') + '" data-id="' + img.id + '">';
            html += '<div class="img-row-check' + (sel ? ' checked' : '') + '" onclick="event.stopPropagation();ImagesPage.toggleSelect(' + img.id + ')">' + (sel ? '<i class="fa-solid fa-check" style="font-size:10px"></i>' : '') + '</div>';
            html += '<div class="img-row-thumb" onclick="' + (selectMode ? 'ImagesPage.toggleSelect(' + img.id + ')' : 'ImagesPage.preview(' + img.id + ')') + '"><img src="' + escAttr(thumbUrl) + '" alt="' + escAttr(img.file_name) + '" loading="lazy"></div>';
            html += '<div class="img-row-name" onclick="' + (selectMode ? 'ImagesPage.toggleSelect(' + img.id + ')' : 'ImagesPage.preview(' + img.id + ')') + '" title="' + escAttr(img.file_name) + '">' + escHtml(img.file_name) + '</div>';
            html += '<div class="img-row-dims">' + escHtml(dims) + '</div>';
            html += '<div class="img-row-size">' + formatFileSize(img.file_size) + '</div>';
            html += '<div class="img-row-date">' + escHtml(dateStr) + '</div>';
            html += '<div class="img-row-url"><span class="img-row-url-text" title="' + escAttr(fullUrl) + '">' + escHtml(fullUrl) + '</span>';
            html += '<button class="img-row-copy" onclick="event.stopPropagation();ImagesPage.copyUrl(\'' + escAttr(escJs(fullUrl)) + '\')" title="复制链接" aria-label="复制链接"><i class="fa-solid fa-copy"></i></button></div>';
            html += '<div style="display:flex;gap:2px;align-items:center;flex-shrink:0">';
            html += '<button class="img-row-del" onclick="event.stopPropagation();ImagesPage.deleteImage(' + img.id + ',\'' + escAttr(escJs(img.file_name)) + '\')" title="删除" aria-label="删除图片"><i class="fa-solid fa-trash-can"></i></button>';
            html += '</div>';
            html += '</div>';
        }
        html += '</div>';
        listEl.innerHTML = html;
    }

    // === Toggle View ===
    function toggleView(mode) {
        currentView = mode;
        localStorage.setItem(IMAGES_KEY, mode);
        setViewMode(mode);
        if (selectMode) exitSelectMode();
        renderCurrentView();
    }

    function setViewMode(mode) {
        var gridBtn = document.getElementById('view-grid');
        var listBtn = document.getElementById('view-list');
        if (mode === 'grid') {
            gridBtn.classList.add('active');
            listBtn.classList.remove('active');
        } else {
            gridBtn.classList.remove('active');
            listBtn.classList.add('active');
        }
        currentView = mode;
    }

    // === Upload ===
    function uploadFiles(fileList) {
        var files = Array.prototype.slice.call(fileList);
        var imageFiles = files.filter(function(f) {
            return f.type && f.type.indexOf('image/') === 0;
        });
        if (imageFiles.length === 0) {
            BSDialog.toast('请选择图片文件', 'warning');
            return;
        }
        var progressEl = document.getElementById('upload-progress');
        var successCount = 0;
        var errorCount = 0;

        var promises = imageFiles.map(function(file) {
            var itemId = 'upload-' + Date.now() + '-' + Math.random().toString(36).substr(2, 4);
            var itemEl = document.createElement('div');
            itemEl.className = 'upload-item uploading';
            itemEl.id = itemId;
            itemEl.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i><span class="upload-name" title="' + escAttr(file.name) + '">' + escHtml(file.name) + '</span>';
            progressEl.appendChild(itemEl);

            var formData = new FormData();
            formData.append('file', file);

            return csrfFetch('/api/uploads', {
                method: 'POST',
                body: formData
            }).then(function(r) {
                return r.json();
            }).then(function(res) {
                if (res.code !== 0) {
                    throw new Error(res.message || '上传失败');
                }
                itemEl.className = 'upload-item success';
                itemEl.innerHTML = '<i class="fa-solid fa-circle-check"></i><span class="upload-name" title="' + escAttr(file.name) + '">' + escHtml(file.name) + '</span>';
                successCount++;
                // Auto-remove after 2s
                setTimeout(function() {
                    itemEl.style.opacity = '0';
                    itemEl.style.transition = 'opacity 0.3s ease';
                    setTimeout(function() { itemEl.remove(); }, 300);
                }, 2000);
            }).catch(function(err) {
                itemEl.className = 'upload-item error';
                itemEl.innerHTML = '<i class="fa-solid fa-circle-xmark"></i><span class="upload-name" title="' + escAttr(err.message || '上传失败') + '">' + escHtml(file.name) + '</span>';
                errorCount++;
                // Auto-remove after 3s
                setTimeout(function() {
                    itemEl.style.opacity = '0';
                    itemEl.style.transition = 'opacity 0.3s ease';
                    setTimeout(function() { itemEl.remove(); }, 300);
                }, 3000);
            });
        });

        Promise.all(promises).then(function() {
            if (successCount > 0) {
                BSDialog.toast('成功上传 ' + successCount + ' 张图片', 'success');
                loadImages(currentPage);
            }
            if (errorCount > 0) {
                BSDialog.toast(errorCount + ' 张图片上传失败', 'error');
            }
        });
    }

    // === Delete ===
    function confirmDeleteImage(id, name) {
        BSDialog.confirm2('确定删除图片 "' + name + '"？').then(function(ok) {
            if (!ok) return;
            csrfFetch('/api/uploads/' + id, { method: 'DELETE' })
                .then(function(r) { return r.json(); })
                .then(function(res) {
                    if (res.code !== 0) {
                        BSDialog.toast(res.message || '删除失败', 'error');
                        return;
                    }
                    BSDialog.toast('图片已删除', 'success');
                    loadImages(currentData.length === 0 && currentPage > 1 ? currentPage - 1 : currentPage);
                })
                .catch(function() {
                    BSDialog.toast('删除失败', 'error');
                });
        });
    }

    function deleteImage(id, name) {
        confirmDeleteImage(id, name);
    }

    function deleteImageFromPreview(id, name) {
        closePreview();
        confirmDeleteImage(id, name);
    }

    // === Preview ===
    function preview(id) {
        var img = null;
        for (var i = 0; i < currentData.length; i++) {
            if (currentData[i].id === id) { img = currentData[i]; break; }
        }
        if (!img) return;

        var fullUrl = img.url;
        var dims = (img.width && img.height) ? img.width + ' x ' + img.height : '-';
        var dateStr = formatDate(img.create_time);
        var sizeStr = formatFileSize(img.file_size);

        var overlay = document.getElementById('bs-dialog-overlay');
        if (!overlay) {
            overlay = document.createElement('div');
            overlay.id = 'bs-dialog-overlay';
            overlay.className = 'bs-dialog-overlay';
            overlay.setAttribute('role', 'dialog');
            overlay.setAttribute('aria-modal', 'true');
            document.body.appendChild(overlay);
        }
        var box = document.getElementById('bs-dialog-box');
        if (!box) {
            box = document.createElement('div');
            box.id = 'bs-dialog-box';
            box.className = 'bs-dialog-box';
            box.setAttribute('role', 'document');
            overlay.appendChild(box);
        }

        var html = '<div class="img-preview-dialog">';
        html += '<div class="bs-dialog-title" style="text-align:left">图片预览</div>';
        html += '<img src="' + escAttr(fullUrl) + '" alt="' + escAttr(img.file_name) + '" style="max-width:100%;max-height:60vh;border-radius:var(--radius-md);background:var(--color-gray-100);">';
        html += '<div class="img-preview-info">';
        html += '<div><strong>文件名：</strong>' + escHtml(img.file_name) + '</div>';
        html += '<div><strong>尺寸：</strong>' + escHtml(dims) + '</div>';
        html += '<div><strong>大小：</strong>' + escHtml(sizeStr) + '</div>';
        html += '<div><strong>日期：</strong>' + escHtml(dateStr) + '</div>';
        html += '</div>';
        html += '<div class="img-preview-actions">';
        html += '<button class="bs-btn bs-btn-cancel" onclick="ImagesPage.closePreview()">关闭</button>';
        html += '<button class="bs-btn" style="background:var(--color-gray-100);color:var(--color-gray-700)" onclick="ImagesPage.copyUrl(\'' + escAttr(escJs(fullUrl)) + '\')"><i class="fa-solid fa-copy" style="margin-right:4px;font-size:12px"></i>复制链接</button>';
        html += '<button class="bs-btn" style="background:var(--color-danger);color:white" onclick="ImagesPage.deleteImageFromPreview(' + img.id + ',\'' + escAttr(escJs(img.file_name)) + '\')"><i class="fa-solid fa-trash-can" style="margin-right:4px;font-size:12px"></i>删除</button>';
        html += '</div>';
        html += '</div>';

        box.innerHTML = html;
        overlay.classList.add('active');
        if (window.BookStarkScrollLock) BookStarkScrollLock.lock('image-preview');

        // Close on overlay click
        overlay.onclick = function(e) {
            if (e.target === overlay) closePreview();
        };
        // Close on Escape
        document.addEventListener('keydown', _previewEscHandler);
    }

    var _previewEscHandler = function(e) {
        if (e.key === 'Escape') closePreview();
    };

    function closePreview() {
        var overlay = document.getElementById('bs-dialog-overlay');
        if (overlay) overlay.classList.remove('active');
        if (window.BookStarkScrollLock) BookStarkScrollLock.unlock('image-preview');
        document.removeEventListener('keydown', _previewEscHandler);
    }

    // === Copy URL ===
    function copyUrl(url) {
        // Make absolute URL
        var absoluteUrl = url;
        if (url && url.charAt(0) === '/') {
            absoluteUrl = window.location.origin + url;
        }
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(absoluteUrl).then(function() {
                BSDialog.toast('已复制链接', 'success');
            }).catch(function() {
                fallbackCopy(absoluteUrl);
            });
        } else {
            fallbackCopy(absoluteUrl);
        }
    }

    function fallbackCopy(text) {
        var ta = document.createElement('textarea');
        ta.value = text;
        ta.style.position = 'fixed';
        ta.style.left = '-9999px';
        document.body.appendChild(ta);
        ta.select();
        try {
            document.execCommand('copy');
            BSDialog.toast('已复制链接', 'success');
        } catch(e) {
            BSDialog.toast('复制失败，请手动复制', 'error');
        }
        document.body.removeChild(ta);
    }

    // === Format helpers ===
    function formatFileSize(bytes) {
        if (!bytes || bytes === 0) return '0 B';
        var units = ['B', 'KB', 'MB', 'GB'];
        var i = 0;
        var size = bytes;
        while (size >= 1024 && i < units.length - 1) {
            size /= 1024;
            i++;
        }
        return size.toFixed(i === 0 ? 0 : 1) + ' ' + units[i];
    }

    function formatDate(dateStr) {
        if (!dateStr) return '-';
        try {
            var d = new Date(dateStr);
            var y = d.getFullYear();
            var m = String(d.getMonth() + 1).padStart(2, '0');
            var day = String(d.getDate()).padStart(2, '0');
            return y + '-' + m + '-' + day;
        } catch(e) {
            return dateStr.substring(0, 10);
        }
    }

    // === Expose public API ===
    return {
        init: init,
        preview: preview,
        closePreview: closePreview,
        deleteImage: deleteImage,
        deleteImageFromPreview: deleteImageFromPreview,
        copyUrl: copyUrl,
        toggleSelect: toggleSelect,
        selectAll: selectAll,
        batchDelete: batchDelete,
        exitSelectMode: exitSelectMode
    };
})();

// escHtml, escAttr, escJs are global functions from utils.js

document.addEventListener('DOMContentLoaded', function() {
    ImagesPage.init();
});
