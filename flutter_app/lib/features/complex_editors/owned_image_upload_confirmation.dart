import 'package:flutter/material.dart';
import '../../core/owned_complex_image_picker_action.dart';

/// Existing editor layout stays intact. Back/default always keeps the draft.
Future<bool> confirmOwnedImageUpload(
  BuildContext context,
  OwnedImageConfirmation selection, {
  bool english = false,
  bool protectedDocument = false,
}) async {
  var approved = false;
  return await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(english ? 'Upload image' : '上传图片'),
            scrollable: true,
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selection.name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    english
                        ? 'Image: ${selection.width} × ${selection.height} · ${(selection.bytes + 1023) ~/ 1024} KB'
                        : '图片：${selection.width} × ${selection.height} · ${(selection.bytes + 1023) ~/ 1024} KB',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    english
                        ? (protectedDocument
                              ? 'Uploaded images can be accessed through their server address and are not protected by the note password. Uploading does not save the document; Save is still required after insertion.'
                              : 'Uploaded images can be accessed through their server address. Uploading does not save the document; Save is still required after insertion.')
                        : (protectedDocument
                              ? '图片上传到服务器后可通过地址访问，不受笔记密码保护。上传不会保存文档；插入后仍需明确保存。'
                              : '图片上传到服务器后可通过地址访问。上传不会保存文档；插入后仍需明确保存。'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: approved,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      english ? 'I agree to upload this image' : '我同意上传这张图片',
                    ),
                    onChanged: (value) =>
                        setState(() => approved = value == true),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(english ? 'Keep editing' : '继续编辑'),
              ),
              FilledButton(
                onPressed: approved ? () => Navigator.pop(context, true) : null,
                child: Text(english ? 'Upload image' : '上传图片'),
              ),
            ],
          ),
        ),
      ) ??
      false;
}
