import 'package:flutter/material.dart';

const dockerInk = Color(0xff0c192e),
    dockerBlue = Color(0xff0b57ee),
    dockerCard = Color(0xffeaf2ff);

class DockerTargetStrip extends StatelessWidget {
  const DockerTargetStrip({
    super.key,
    required this.title,
    this.icon = Icons.dns_outlined,
  });
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: dockerCard,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, color: dockerInk, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: dockerInk,
            ),
          ),
        ),
      ],
    ),
  );
}

String dockerStatusTitle(String status, bool english) => switch (status) {
  'running' => english ? 'Running' : '运行中',
  'stopped' => english ? 'Stopped' : '已停止',
  'paused' => english ? 'Paused' : '已暂停',
  'restarting' => english ? 'Restarting' : '重启中',
  _ => english ? 'Unknown' : '未知',
};

class DockerStatusBadge extends StatelessWidget {
  const DockerStatusBadge({
    super.key,
    required this.status,
    this.english = false,
    this.solid = false,
  });
  final String status;
  final bool english, solid;
  @override
  Widget build(BuildContext context) {
    final running = status == 'running', stopped = status == 'stopped';
    final bg = running
        ? (solid ? const Color(0xff2e8b35) : const Color(0xffd9f5dc))
        : stopped
        ? const Color(0xffe1e5e9)
        : const Color(0xfffff0cf);
    final fg = running
        ? (solid ? Colors.white : const Color(0xff267c30))
        : stopped
        ? const Color(0xff4b5563)
        : const Color(0xff8a5a00);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        dockerStatusTitle(status, english),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class DockerInfoCard extends StatelessWidget {
  const DockerInfoCard({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Material(
    color: dockerCard,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              const Divider(height: 1, color: Color(0xffcbd5e1)),
          ],
        ],
      ),
    ),
  );
}

class DockerMetadataRow extends StatelessWidget {
  const DockerMetadataRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
    this.selectable = false,
  });
  final IconData icon;
  final String label, value;
  final Widget? trailing;
  final bool selectable;
  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.textScalerOf(context).scale(14) > 22;
    final content = selectable
        ? SelectableText(
            value,
            style: const TextStyle(fontSize: 14, color: dockerInk),
          )
        : Text(
            value,
            style: const TextStyle(fontSize: 14, color: dockerInk),
            textAlign: large ? TextAlign.start : TextAlign.end,
          );
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: dockerInk),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: dockerInk,
            ),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: large
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: content),
                    ?trailing,
                  ],
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(width: 108, child: title),
                const SizedBox(width: 10),
                Expanded(child: content),
                ?trailing,
              ],
            ),
    );
  }
}

String dockerTimeLabel(String value) {
  if (value.isEmpty || value.startsWith('0001-01-01')) return '—';
  final parsed = DateTime.tryParse(value)?.toLocal();
  if (parsed == null) return value;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} ${two(parsed.hour)}:${two(parsed.minute)}';
}
