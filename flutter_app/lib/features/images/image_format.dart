String imageSizeLabel(int? bytes, {bool english = false}) {
  if (bytes == null) return english ? 'Size unknown' : '大小未知';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String imageCategoryLabel(String value, {bool english = false}) =>
    switch (value) {
      'editor' => english ? 'Editor' : '编辑器',
      'note' => english ? 'Note' : '笔记',
      'drawing' => english ? 'Drawing' : '画板',
      '' => english ? 'Uncategorized' : '未分类',
      _ => value,
    };
