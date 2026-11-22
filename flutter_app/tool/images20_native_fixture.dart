// PREPARED/UNRUN. Actual production image pages/repositories, synthetic data.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_attachments.dart';
import 'package:bookstark_flutter/core/local_images_repository.dart';
import 'package:bookstark_flutter/core/images_repository.dart';
import 'package:bookstark_flutter/features/images/images_page.dart';
import 'package:bookstark_flutter/widgets/native_image.dart';

void main() => runApp(const MaterialApp(home: OwnedImages20Fixture()));

class OwnedImages20Fixture extends StatefulWidget {
  const OwnedImages20Fixture({super.key});
  @override
  State<OwnedImages20Fixture> createState() => _State();
}

class _State extends State<OwnedImages20Fixture> {
  static const run = String.fromEnvironment('OWNED_IMAGES_RUN');
  static const port = int.fromEnvironment('OWNED_IMAGES_PORT');
  LocalStore? store;
  LocalImagesRepository? local;
  RemoteImagesRepository? remote;
  BookstarkClient? client;
  bool current = true, ready = false, english = false;
  int scopeEpoch = 0;
  ImageLibraryOwner? activeOwner;
  final control = http.Client();
  Timer? controlTimer;
  bool polling = false, transitioning = false;
  Future<void> _phase(String phase) async {
    final response = await control.post(
      Uri.parse('http://127.0.0.1:$port/owned-images-control'),
      headers: {'X-Owned-Run': run, 'content-type': 'application/json'},
      body: jsonEncode({'phase': phase}),
    );
    if (response.statusCode != 200 || response.bodyBytes.length > 1024) {
      throw StateError('Owned control receipt');
    }
  }

  Future<void> _poll() async {
    if (!mounted || polling || transitioning) return;
    polling = true;
    try {
      final response = await control.get(
        Uri.parse('http://127.0.0.1:$port/owned-images-control'),
        headers: {'X-Owned-Run': run},
      );
      if (response.statusCode != 200 || response.bodyBytes.length > 1024) {
        throw StateError('Owned control');
      }
      final value = jsonDecode(response.body);
      if (value is! Map || value['format'] != 1 || value['retire'] is! bool) {
        throw StateError('Owned control shape');
      }
      if (value['retire'] == true && scopeEpoch == 0) {
        transitioning = true;
        await _phase('drainStarted');
        final before = activeOwner;
        if (before == null) {
          throw StateError('Actual active image owner missing');
        }
        await before.retireAndDrain();
        await _phase('nativeDrained');
        if (!mounted) return;
        // Only after the actual owner/native barrier completes may B be activated.
        scopeEpoch = 1;
        final old = remote, oldClient = client;
        final next = BookstarkClient('http://127.0.0.1:$port');
        next.restoreSession({'token': 'owned-images20-B-$run'});
        client = next;
        remote = RemoteImagesRepository(
          next,
          isCurrentScope: () => mounted && current && scopeEpoch == 1,
        );
        old?.dispose();
        oldClient?.close();
        Navigator.of(context).popUntil((route) => route.isFirst);
        await _phase('scopeBActive');
        if (mounted) setState(() => ready = true);
      }
    } finally {
      polling = false;
    }
  }

  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(run) ||
          port < 1024 ||
          port > 65535) {
        throw StateError('Owned binding');
      }
      final epoch = scopeEpoch;
      final temp = await getTemporaryDirectory();
      final dbStore = LocalStore(path: '${temp.path}/owned_images20_$run.db');
      store = dbStore;
      final files = Directory('${temp.path}/owned_images20_$run/files');
      final media = LocalAttachments(files, maintenance: dbStore.maintenance);
      local = LocalImagesRepository(
        dbStore,
        media,
        dimensionsReader: nativeImageDimensions,
        isCurrentScope: () => mounted && current && scopeEpoch == epoch,
      );
      final db = await dbStore.database;
      final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM local_images');
      final seedClaim = File('${temp.path}/owned_images20_$run/seed-claimed');
      await seedClaim.parent.create(recursive: true);
      if (rows.single['n'] == 0 && !await seedClaim.exists()) {
        // Claim before any seed INSERT. A failed/partially deleted fixture never replays seeding.
        await seedClaim.create(exclusive: true);
        final bytes = base64Decode(
          'R0lGODlhEAAIAPcfMQAAACQAAEgAAGwAAJAAALQAANgAAPwAAAAkACQkAEgkAGwkAJAkALQkANgkAPwkAABIACRIAEhIAGxIAJBIALRIANhIAPxIAABsACRsAEhsAGxsAJBsALRsANhsAPxsAACQACSQAEiQAGyQAJCQALSQANiQAPyQAAC0ACS0AEi0AGy0AJC0ALS0ANi0APy0AADYACTYAEjYAGzYAJDYALTYANjYAPzYAAD8ACT8AEj8AGz8AJD8ALT8ANj8APz8AAAAVSQAVUgAVWwAVZAAVbQAVdgAVfwAVQAkVSQkVUgkVWwkVZAkVbQkVdgkVfwkVQBIVSRIVUhIVWxIVZBIVbRIVdhIVfxIVQBsVSRsVUhsVWxsVZBsVbRsVdhsVfxsVQCQVSSQVUiQVWyQVZCQVbSQVdiQVfyQVQC0VSS0VUi0VWy0VZC0VbS0Vdi0Vfy0VQDYVSTYVUjYVWzYVZDYVbTYVdjYVfzYVQD8VST8VUj8VWz8VZD8VbT8Vdj8Vfz8VQAAqiQAqkgAqmwAqpAAqrQAqtgAqvwAqgAkqiQkqkgkqmwkqpAkqrQkqtgkqvwkqgBIqiRIqkhIqmxIqpBIqrRIqthIqvxIqgBsqiRsqkhsqmxsqpBsqrRsqthsqvxsqgCQqiSQqkiQqmyQqpCQqrSQqtiQqvyQqgC0qiS0qki0qmy0qpC0qrS0qti0qvy0qgDYqiTYqkjYqmzYqpDYqrTYqtjYqvzYqgD8qiT8qkj8qmz8qpD8qrT8qtj8qvz8qgAA/yQA/0gA/2wA/5AA/7QA/9gA//wA/wAk/yQk/0gk/2wk/5Ak/7Qk/9gk//wk/wBI/yRI/0hI/2xI/5BI/7RI/9hI//xI/wBs/yRs/0hs/2xs/5Bs/7Rs/9hs//xs/wCQ/ySQ/0iQ/2yQ/5CQ/7SQ/9iQ//yQ/wC0/yS0/0i0/2y0/5C0/7S0/9i0//y0/wDY/yTY/0jY/2zY/5DY/7TY/9jY//zY/wD8/yT8/0j8/2z8/5D8/7T8/9j8//z8/yH/C05FVFNDQVBFMi4wAwEAAAAh+QQEFAAfACwAAAAAEAAIAAAIGgAPCBxIsKDBgwgTDjRwkKHChxAjQnRYkGJAACH5BAUUAAAALAAAAAAQAAgAAAgaAAEBG0gQmMCCCBMqXMiwIcODCCE6nEhxYkAAOw==',
        );
        await local!.upload(
          ImageUploadPayload.fromBytes(
            name: 'Owned Animated GIF.gif',
            bytes: bytes,
            category: ImageCategory.note,
          ),
        );
        final svg = Uint8List.fromList(
          utf8.encode(
            '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><rect width="32" height="32" fill="blue"/></svg>',
          ),
        );
        await local!.upload(
          ImageUploadPayload.fromBytes(
            name: 'Owned Vector 图.svg',
            bytes: svg,
            category: ImageCategory.editor,
          ),
        );
      }
      final transport = BookstarkClient('http://127.0.0.1:$port');
      transport.restoreSession({'token': 'owned-images20-$run'});
      client = transport;
      remote = RemoteImagesRepository(
        transport,
        isCurrentScope: () => mounted && current && scopeEpoch == epoch,
      );
      if (mounted) {
        setState(() => ready = true);
        controlTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
          unawaited(
            _poll().catchError((Object _) {
              if (mounted) setState(() => error = 'Owned control failed');
            }),
          );
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Owned images fixture initialization failed');
      }
    }
  }

  Future<void> _open(bool remoteMode) async {
    if (!current || !ready) return;
    final epoch = scopeEpoch;
    final owner = ImageLibraryOwner(
      isCurrentScope: () => mounted && current && scopeEpoch == epoch,
    );
    activeOwner = owner;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ImagesPage(
          repository: remoteMode ? remote! : local!,
          owner: owner,
          english: english,
        ),
      ),
    );
    if (identical(activeOwner, owner)) activeOwner = null;
  }

  @override
  void dispose() {
    current = false;
    controlTimer?.cancel();
    control.close();
    unawaited(activeOwner?.retireAndDrain() ?? Future<void>.value());
    local?.dispose();
    remote?.dispose();
    client?.close();
    final db = store;
    if (db != null) unawaited(db.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Owned Images20 fixture')),
    body: ListView(
      children: [
        if (error != null) Text(error!),
        if (!ready && error == null) const CircularProgressIndicator(),
        if (ready) ...[
          const Text('Owned fixture ready'),
          SwitchListTile(
            title: const Text('English'),
            value: english,
            onChanged: (v) => setState(() => english = v),
          ),
          FilledButton(
            onPressed: scopeEpoch == 0 ? () => _open(false) : null,
            child: const Text('Open local Images'),
          ),
          FilledButton(
            onPressed: () => _open(true),
            child: const Text('Open remote Images'),
          ),
          FilledButton(
            onPressed: () {
              current = false;
              setState(() => ready = false);
            },
            child: const Text('Retire fixture owner'),
          ),
        ],
      ],
    ),
  );
}
