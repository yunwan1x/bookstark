/* ===== BookStark Pagination Component ===== */
function renderPagination(containerId, currentPage, totalPages, onPageClick, opts) {
    var container = document.getElementById(containerId);
    if (!container) return;

    // 不超过1页时不显示分页
    if (totalPages <= 1) {
        container.innerHTML = '';
        return;
    }

    var compact = opts && opts.compact;
    var hideText = opts && opts.hideText;
    var customMax = opts && opts.maxVisible;
    var maxVisible = customMax || (compact ? 3 : 5);

    var html = '';

    // 上一页
    html += '<button class="page-btn' + (compact ? ' page-btn-compact' : '') + '" ' + (currentPage <= 1 ? 'disabled' : '') +
            ' data-page="' + (currentPage - 1) + '"' +
            (currentPage <= 1 ? '' : ' aria-label="上一页"') + '>' +
            '<i class="fa-solid fa-chevron-left"></i></button>';

    // 页码（首尾页计入 maxVisible，最多 maxVisible 个页码按钮）
    if (totalPages <= maxVisible) {
        // 页数不多，全部显示
        for (var i = 1; i <= totalPages; i++) {
            html += '<button class="page-btn' + (i === currentPage ? ' active' : '') + (compact ? ' page-btn-compact' : '') +
                    '" data-page="' + i + '" aria-label="第' + i + '页"' +
                    (i === currentPage ? ' aria-current="page"' : '') + '>' + i + '</button>';
        }
    } else {
        var showFirst = currentPage > 3;
        var showLast = currentPage < totalPages - 2;
        var rangeSize = maxVisible - (showFirst ? 1 : 0) - (showLast ? 1 : 0);
        var rangeStart, rangeEnd;

        if (!showFirst && showLast) {
            rangeStart = 1;
            rangeEnd = rangeSize;
        } else if (showFirst && !showLast) {
            rangeEnd = totalPages;
            rangeStart = totalPages - rangeSize + 1;
        } else {
            rangeStart = currentPage - Math.floor((rangeSize - 1) / 2);
            rangeEnd = rangeStart + rangeSize - 1;
        }

        if (showFirst) {
            html += '<button class="page-btn' + (compact ? ' page-btn-compact' : '') + '" data-page="1" aria-label="第1页">1</button>';
            if (rangeStart > 2) html += '<span class="page-ellipsis px-1 text-slate-400">...</span>';
        }

        for (var i = rangeStart; i <= rangeEnd; i++) {
            html += '<button class="page-btn' + (i === currentPage ? ' active' : '') + (compact ? ' page-btn-compact' : '') +
                    '" data-page="' + i + '" aria-label="第' + i + '页"' +
                    (i === currentPage ? ' aria-current="page"' : '') + '>' + i + '</button>';
        }

        if (showLast) {
            if (rangeEnd < totalPages - 1) html += '<span class="page-ellipsis px-1 text-slate-400">...</span>';
            html += '<button class="page-btn' + (compact ? ' page-btn-compact' : '') + '" data-page="' + totalPages + '" aria-label="第' + totalPages + '页">' + totalPages + '</button>';
        }
    }

    // 下一页
    html += '<button class="page-btn' + (compact ? ' page-btn-compact' : '') + '" ' + (currentPage >= totalPages ? 'disabled' : '') +
            ' data-page="' + (currentPage + 1) + '"' +
            (currentPage >= totalPages ? '' : ' aria-label="下一页"') + '>' +
            '<i class="fa-solid fa-chevron-right"></i></button>';

    // 总数显示
    if (opts && opts.showCount && opts.totalItems !== undefined) {
        html += '<span class="page-btn-info">共 ' + opts.totalItems + ' 项</span>';
    }

    container.innerHTML = html;

    // 绑定事件
    container.querySelectorAll('.page-btn[data-page]').forEach(function(btn) {
        btn.addEventListener('click', function() {
            var page = parseInt(this.getAttribute('data-page'));
            if (page >= 1 && page <= totalPages && page !== currentPage) {
                onPageClick(page);
            }
        });
    });
}