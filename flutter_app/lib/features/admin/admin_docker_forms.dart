import 'package:flutter/material.dart';
import 'admin_asset_models.dart';
import 'admin_docker_models.dart';
import 'admin_docker_repository.dart';
import 'admin_docker_theme.dart';

class DockerCreatePage extends StatefulWidget {
  const DockerCreatePage({
    super.key,
    required this.host,
    required this.onReturn,
    required this.onReview,
    this.english = false,
  });
  final AdminAssetHostMetadata host;
  final VoidCallback onReturn;
  final Future<bool> Function(DockerCreateDraft) onReview;
  final bool english;
  @override
  State<DockerCreatePage> createState() => _DockerCreateState();
}

class _OptionFields {
  _OptionFields(this.keys)
    : values = {for (final key in keys) key: TextEditingController()};
  final List<String> keys;
  final Map<String, TextEditingController> values;
  String choice = '';
  Map<String, String> get data => {
    for (final key in keys) key: values[key]!.text,
  };
  void dispose() {
    for (final c in values.values) {
      c.dispose();
    }
  }
}

class _DockerCreateState extends State<DockerCreatePage> {
  final name = TextEditingController(),
      image = TextEditingController(),
      command = TextEditingController(),
      network = TextEditingController(),
      memory = TextEditingController(),
      cpus = TextEditingController();
  final ports = <_OptionFields>[],
      volumes = <_OptionFields>[],
      env = <_OptionFields>[];
  var step = 0, policy = 'no';
  bool start = false, privileged = false, busy = false;
  String? error;
  String t(String zh, String en) => widget.english ? en : zh;
  Widget field(
    TextEditingController c,
    String zh,
    String en, {
    bool secret = false,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      enabled: !busy,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(labelText: t(zh, en), helperText: hint),
    ),
  );
  Widget section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: const Color(0xffeaf2ff),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    ),
  );
  void add(List<_OptionFields> list, List<String> keys, String choice) {
    setState(() {
      final row = _OptionFields(keys);
      if (keys.first == 'host_ip') row.values['host_ip']!.text = '127.0.0.1';
      row.choice = choice;
      list.add(row);
    });
  }

  Widget options(
    List<_OptionFields> list,
    String zh,
    String en,
    List<String> keys,
    List<String> labelsZh,
    List<String> labelsEn, {
    List<String> choices = const [],
    String choiceKey = '',
    bool secret = false,
  }) => section(t(zh, en), [
    for (final row in list)
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < keys.length; i++)
              field(
                row.values[keys[i]]!,
                labelsZh[i],
                labelsEn[i],
                secret: secret && keys[i] == 'value',
              ),
            if (choices.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: row.choice,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t(
                    choiceKey == 'protocol' ? '协议' : '访问模式',
                    choiceKey == 'protocol' ? 'Protocol' : 'Access mode',
                  ),
                ),
                items: [
                  for (final value in choices)
                    DropdownMenuItem(value: value, child: Text(value)),
                ],
                onChanged: busy
                    ? null
                    : (value) =>
                          setState(() => row.choice = value ?? choices.first),
              ),
            TextButton(
              onPressed: busy
                  ? null
                  : () {
                      setState(() => list.remove(row));
                      row.dispose();
                    },
              child: Text(t('移除此项', 'Remove this item')),
            ),
          ],
        ),
      ),
    OutlinedButton.icon(
      key: ValueKey('docker-add-${keys.first}'),
      onPressed: busy
          ? null
          : () => add(list, keys, choices.isEmpty ? '' : choices.first),
      icon: const Icon(Icons.add),
      label: Text(t('添加一项', 'Add item')),
    ),
  ]);
  DockerCreateDraft draft() => DockerCreateDraft(
    name: name.text,
    image: image.text,
    command: command.text,
    restartPolicy: policy,
    startAfterCreate: start,
    ports: [
      for (final row in ports) {...row.data, 'protocol': row.choice},
    ],
    volumes: [
      for (final row in volumes) {...row.data, 'mode': row.choice},
    ],
    env: [for (final row in env) row.data],
    network: network.text,
    privileged: privileged,
    memory: memory.text,
    cpus: cpus.text,
  );
  Future<void> next() async {
    try {
      if (step == 0) {
        dockerObjectName(name.text);
        dockerImageReference(image.text);
        dockerText(command.text);
        setState(() {
          step = 1;
          error = null;
        });
        return;
      }
      final value = draft();
      value.toRequest();
      setState(() {
        busy = true;
        error = null;
      });
      final attempted = await widget.onReview(value);
      if (!mounted) return;
      if (attempted) {
        widget.onReturn();
        return;
      }
    } on FormatException {
      if (mounted) {
        setState(
          () => error = t(
            '配置无效，请核对名称、镜像及各项高级设置。',
            'Invalid configuration. Check the name, image and advanced settings.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AdminDockerScaffold(
    appBar: AppBar(
      title: Text(t('创建容器', 'Create container')),
      leading: IconButton(
        onPressed: busy ? null : widget.onReturn,
        tooltip: t('返回', 'Back'),
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.host.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            step == 0
                ? t('1 / 3 · 基本设置', '1 / 3 · Basics')
                : t('2 / 3 · 配置', '2 / 3 · Configuration'),
          ),
          const SizedBox(height: 16),
          if (step == 0) ...[
            section(t('基本设置', 'Basics'), [
              field(name, '容器名称', 'Container name'),
              field(image, '镜像', 'Image'),
              field(
                command,
                '单个命令参数（可留空）',
                'Single command argument (optional)',
                hint: t(
                  '完整文字作为一个参数传递，不拆分参数或执行 shell。留空使用镜像默认命令。',
                  'The entire text is one argument. No argument splitting or shell execution. Leave blank for the image default.',
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: policy,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t('重启策略', 'Restart policy'),
                ),
                items: [
                  for (final p in dockerPolicies)
                    DropdownMenuItem(value: p, child: Text(p)),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() => policy = value ?? 'no'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: start,
                onChanged: busy ? null : (v) => setState(() => start = v),
                title: Text(t('创建后启动', 'Start after create')),
                subtitle: Text(
                  t(
                    '创建和启动可能部分成功，失败时不会自动重试。',
                    'Creation and startup may partially succeed. Failures are never retried automatically.',
                  ),
                ),
              ),
            ]),
          ] else ...[
            Text(
              t(
                '填写主机端口和IPv4地址；0.0.0.0表示所有IPv4接口。',
                'Set an explicit host port and IPv4 address. 0.0.0.0 binds all IPv4 interfaces.',
              ),
            ),
            const SizedBox(height: 12),
            options(
              ports,
              '端口',
              'Ports',
              ['host_ip', 'host_port', 'container_port'],
              ['IPv4绑定地址', '主机端口', '容器端口'],
              ['IPv4 bind address', 'Host port', 'Container port'],
              choices: ['tcp', 'udp', 'sctp'],
              choiceKey: 'protocol',
            ),
            options(
              volumes,
              '挂载',
              'Mounts',
              ['host_path', 'container_path'],
              ['主机路径或卷名', '容器绝对路径'],
              ['Host path or volume name', 'Absolute container path'],
              choices: ['ro', 'rw'],
              choiceKey: 'mode',
            ),
            options(env, '环境变量', 'Environment', ['key', 'value'], ['键', '值'], [
              'Key',
              'Value',
            ], secret: true),
            section(t('高级设置', 'Advanced'), [
              field(network, '网络（可留空）', 'Network (optional)'),
              field(memory, '内存限制（如512m）', 'Memory limit (e.g. 512m)'),
              field(cpus, 'CPU限制（如1.5）', 'CPU limit (e.g. 1.5)'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: privileged,
                onChanged: busy ? null : (v) => setState(() => privileged = v),
                title: Text(t('特权容器', 'Privileged container')),
              ),
              if (privileged)
                Text(
                  t(
                    '此设置给予容器额外的主机访问权限，请在下一页核对。',
                    'This grants additional host access. Review it on the next page.',
                  ),
                ),
            ]),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (step == 1)
                OutlinedButton(
                  onPressed: busy ? null : () => setState(() => step = 0),
                  child: Text(t('上一步', 'Previous')),
                ),
              FilledButton(
                onPressed: busy ? null : next,
                child: Text(
                  step == 0
                      ? t('下一步', 'Next')
                      : t('核对配置', 'Review configuration'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    for (final c in [name, image, command, network, memory, cpus]) {
      c.dispose();
    }
    for (final row in [...ports, ...volumes, ...env]) {
      row.dispose();
    }
    super.dispose();
  }
}

class DockerNamedCreatePage extends StatefulWidget {
  const DockerNamedCreatePage({
    super.key,
    required this.resource,
    required this.onReview,
    required this.onReturn,
    this.english = false,
  });
  final DockerResource resource;
  final Future<bool> Function(String, String) onReview;
  final VoidCallback onReturn;
  final bool english;
  @override
  State<DockerNamedCreatePage> createState() => _DockerNamedCreateState();
}

class _DockerNamedCreateState extends State<DockerNamedCreatePage> {
  final name = TextEditingController(), driver = TextEditingController();
  bool busy = false;
  String? error;
  String t(String zh, String en) => widget.english ? en : zh;
  bool get image => widget.resource == DockerResource.images;
  Future<void> review() async {
    try {
      if (image) {
        dockerImageReference(name.text);
      } else {
        dockerObjectName(name.text);
        if (driver.text.isNotEmpty) dockerObjectName(driver.text);
      }
      setState(() {
        busy = true;
        error = null;
      });
      final attempted = await widget.onReview(name.text, driver.text);
      if (mounted && attempted) widget.onReturn();
    } on FormatException {
      if (mounted) {
        setState(() => error = t('请核对名称或驱动。', 'Check the name or driver.'));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AdminDockerScaffold(
    appBar: AppBar(
      title: Text(
        image
            ? t('拉取镜像', 'Pull image')
            : widget.resource == DockerResource.networks
            ? t('创建网络', 'Create network')
            : t('创建数据卷', 'Create volume'),
      ),
      leading: IconButton(
        onPressed: busy ? null : widget.onReturn,
        tooltip: t('返回', 'Back'),
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: name,
            autocorrect: false,
            enableSuggestions: false,
            enabled: !busy,
            decoration: InputDecoration(
              labelText: image ? t('镜像引用', 'Image reference') : t('名称', 'Name'),
            ),
          ),
          if (!image) ...[
            const SizedBox(height: 16),
            TextField(
              controller: driver,
              enabled: !busy,
              decoration: InputDecoration(
                labelText: t(
                  '驱动（留空使用远端默认值）',
                  'Driver (blank uses remote default)',
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (error != null) Text(error!),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : review,
            child: Text(t('下一步', 'Next')),
          ),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    name.dispose();
    driver.dispose();
    super.dispose();
  }
}

class DockerReviewPage extends StatefulWidget {
  const DockerReviewPage({
    super.key,
    required this.host,
    required this.review,
    required this.onConfirm,
    required this.onReturn,
    this.english = false,
  });
  final AdminAssetHostMetadata host;
  final DockerReview review;
  final Future<void> Function() onConfirm;
  final void Function(bool attempted) onReturn;
  final bool english;
  @override
  State<DockerReviewPage> createState() => _DockerReviewState();
}

class _DockerReviewState extends State<DockerReviewPage> {
  bool busy = false, showEnv = false;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  Widget build(BuildContext context) {
    final r = widget.review, body = r.body;
    return AdminDockerScaffold(
      appBar: AppBar(
        title: Text(t('核对 Docker 操作', 'Review Docker operation')),
        leading: IconButton(
          onPressed: busy ? null : () => widget.onReturn(false),
          tooltip: t('返回', 'Back'),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.host.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text('${widget.host.host}:${widget.host.port}'),
            const SizedBox(height: 12),
            Text('${t('主机范围', 'Host scope')} · ${widget.host.id}'),
            const SizedBox(height: 12),
            Text(
              '${t('资源', 'Resource')} · ${dockerResourceTitle(r.resource, widget.english)}',
            ),
            const SizedBox(height: 12),
            Text(dockerActionTitle(r.action, widget.english)),
            if (r.target != null) ...[
              const SizedBox(height: 12),
              Text(t('精确目标', 'Exact target')),
              SelectableText(r.target!),
            ],
            if (r.inspect != null) ...[
              const SizedBox(height: 12),
              Text(r.inspect!.name),
              Text(r.inspect!.image),
            ],
            if (r.action == 'prune') ...[
              const SizedBox(height: 16),
              Text(
                t(
                  '作用于这台主机上符合远端 Docker 默认清理规则的此类资源，包括当前筛选之外的资源。无法撤销。',
                  'Applies to this resource type across the host under the remote Docker default prune rules, including resources outside the current filter. Cannot be undone.',
                ),
              ),
            ],
            if (r.action == 'delete') ...[
              const SizedBox(height: 16),
              Text(
                t(
                  '应用不提供撤销。请确认目标。运行中的容器须先停止。',
                  'The app provides no undo. Verify the target. Running containers must be stopped first.',
                ),
              ),
            ],
            if (body != null) ...[
              const SizedBox(height: 16),
              for (final item in body.entries)
                if (item.key != 'env')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '${dockerFieldTitle(item.key, widget.english)}\n${dockerReviewValue(item.value, widget.english)}',
                    ),
                  ),
              if (body['env'] case final List entries) ...[
                Text('${t('环境变量', 'Environment')} · ${entries.length}'),
                if (entries.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => showEnv = !showEnv),
                    child: Text(
                      showEnv
                          ? t('隐藏临时值', 'Hide temporary values')
                          : t('显示临时值', 'Show temporary values'),
                    ),
                  ),
                if (showEnv)
                  for (final entry in entries)
                    Text('${(entry as Map)['key']}=${entry['value']}'),
              ],
            ],
            const SizedBox(height: 16),
            Text(
              t(
                '确认只提交一次；结果未确认时先重新读取，不自动重试。',
                'Confirm submits once. If the result is unknown, observe it first. No automatic retry.',
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton(
                  onPressed: busy ? null : () => widget.onReturn(false),
                  child: Text(t('取消', 'Cancel')),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() => busy = true);
                          await widget.onConfirm();
                          if (mounted) widget.onReturn(true);
                        },
                  child: Text(t('确认操作', 'Confirm operation')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String dockerResourceTitle(DockerResource resource, bool en) =>
    switch (resource) {
      DockerResource.containers => en ? 'Containers' : '容器',
      DockerResource.networks => en ? 'Networks' : '网络',
      DockerResource.volumes => en ? 'Volumes' : '数据卷',
      DockerResource.images => en ? 'Images' : '镜像',
    };
String dockerActionTitle(String action, bool en) => switch (action) {
  'create' => en ? 'Create / pull' : '创建 / 拉取',
  'start' => en ? 'Start' : '启动',
  'stop' => en ? 'Stop' : '停止',
  'restart' => en ? 'Restart' : '重启',
  'delete' => en ? 'Delete' : '删除',
  'restart-policy' => en ? 'Restart policy' : '重启策略',
  'prune' => en ? 'Prune across host' : '清理整台主机',
  _ => en ? 'Review' : '核对',
};
String dockerFieldTitle(String key, bool en) => switch (key) {
  'name' => en ? 'Name' : '名称',
  'image' => en ? 'Image' : '镜像',
  'command' => en ? 'Single command argument' : '单个命令参数',
  'restart_policy' || 'policy' => en ? 'Restart policy' : '重启策略',
  'start_after_create' => en ? 'Start after create' : '创建后启动',
  'ports' => en ? 'Ports' : '端口',
  'volumes' => en ? 'Mounts' : '挂载',
  'network' => en ? 'Network' : '网络',
  'host_ip' => en ? 'Bind address' : '绑定地址',
  'host_port' => en ? 'Host port' : '主机端口',
  'container_port' => en ? 'Container port' : '容器端口',
  'protocol' => en ? 'Protocol' : '协议',
  'host_path' => en ? 'Host path or volume' : '主机路径或卷',
  'container_path' => en ? 'Container path' : '容器路径',
  'mode' => en ? 'Access mode' : '访问模式',
  'running' => en ? 'Running' : '运行中',
  'exit_code' => en ? 'Exit code' : '退出码',
  'created' => en ? 'Created' : '创建时间',
  'started_at' => en ? 'Started' : '启动时间',
  'finished_at' => en ? 'Finished' : '结束时间',
  'hostname' => en ? 'Hostname' : '主机名',
  'ip_address' => en ? 'IP address' : 'IP地址',
  'driver' => en ? 'Driver' : '驱动',
  'scope' => en ? 'Scope' : '作用域',
  'mountpoint' => en ? 'Mount point' : '挂载位置',
  'size' => en ? 'Size' : '大小',
  'created_since' => en ? 'Created' : '创建时间',
  'created_at' => en ? 'Created at' : '创建时间',
  'privileged' => en ? 'Privileged' : '特权',
  'memory' => en ? 'Memory limit' : '内存限制',
  'cpus' => en ? 'CPU limit' : 'CPU限制',
  _ => key,
};
String dockerReviewValue(Object? value, bool en) {
  if (value is List) {
    return value
        .map(
          (row) => row is Map
              ? row.entries
                    .map(
                      (entry) =>
                          '${dockerFieldTitle(entry.key.toString(), en)}: ${entry.value}',
                    )
                    .join('\n')
              : row.toString(),
        )
        .join('\n');
  }
  return value?.toString() ?? '';
}
